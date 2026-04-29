package com.shaadart.tripping

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Database offline mode retains an internal Auth listener and its foreground
 * refresh timer. Keep the same user in an Auth-only app (no Database instance,
 * hence no internal token listener), and sign out the transport app on pause.
 * Both stores use Firebase's own private credential persistence. No tokens are
 * extracted, logged, encrypted by us or passed across the Flutter channel.
 */
class GroupAuth(context: Context, messenger: BinaryMessenger) {
    private val context = context.applicationContext
    private var observed: FirebaseAuth? = null
    private var observer: FirebaseAuth.IdTokenListener? = null

    init {
        MethodChannel(messenger, "tripping/group_auth").setMethodCallHandler { call, result ->
            try {
                val live = FirebaseAuth.getInstance()
                val app = FirebaseApp.getInstance()
                val holdingApp = FirebaseApp.getApps(context).firstOrNull { it.name == HOLDING }
                    ?: FirebaseApp.initializeApp(context, app.options, HOLDING)
                val holding = FirebaseAuth.getInstance(holdingApp)
                when (call.method) {
                    "restore" -> {
                        val user = live.currentUser
                        if (user != null) {
                            remember(live, holding, result)
                        } else if (holding.currentUser != null) {
                            live.updateCurrentUser(holding.currentUser!!).addOnCompleteListener {
                                if (it.isSuccessful) remember(live, holding, result)
                                else result.error("auth-restore", "Could not restore group sign-in", null)
                            }
                        } else {
                            observe(live, holding)
                            result.success(null)
                        }
                    }
                    "remember" -> remember(live, holding, result)
                    "park" -> {
                        val user = live.currentUser
                        if (user == null) {
                            // Foreground return can re-arm an empty refresh task.
                            live.signOut()
                            result.success(null)
                        }
                        else if (holding.currentUser?.uid != user.uid) {
                            // Sign-in may have completed while pause was queued.
                            // Preserve that identity before cancelling its timer.
                            holding.updateCurrentUser(user).addOnCompleteListener {
                                if (!it.isSuccessful) result.error("auth-preserve", "Could not preserve group sign-in", null)
                                else { live.signOut(); result.success(null) }
                            }
                        } else {
                            live.signOut() // Cancels Auth's refresh timer; does not delete the account.
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("auth-lifecycle", "Could not change group sign-in state", null)
            }
        }
    }

    private fun remember(live: FirebaseAuth, holding: FirebaseAuth, result: MethodChannel.Result) {
        val user = live.currentUser
        if (user == null) { result.success(null); return }
        // Refresh only on an explicit active session, before enabling transport.
        user.getIdToken(false).addOnCompleteListener { token ->
            if (!token.isSuccessful) {
                result.error("auth-refresh", "Could not refresh group sign-in", null)
            } else {
                holding.updateCurrentUser(user).addOnCompleteListener { saved ->
                    if (!saved.isSuccessful) result.error("auth-preserve", "Could not preserve group sign-in", null)
                    else { observe(live, holding); result.success(user.uid) }
                }
            }
        }
    }

    private fun observe(live: FirebaseAuth, holding: FirebaseAuth) {
        if (observed === live) return
        observer?.let { observed?.removeIdTokenListener(it) }
        // Public listeners do not enable Auth's internal token refresher.
        val listener = FirebaseAuth.IdTokenListener { auth ->
            auth.currentUser?.let { holding.updateCurrentUser(it) }
        }
        observed = live
        observer = listener
        live.addIdTokenListener(listener)
    }

    companion object { private const val HOLDING = "tripping-paused-identity-v1" }
}
