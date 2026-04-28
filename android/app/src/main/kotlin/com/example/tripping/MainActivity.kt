package com.example.tripping

import android.Manifest
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Shows the process-wide engine owned by [TrippingApplication], and answers
 * the few Android questions the location plugin does not: notification
 * permission, the "Restricted" battery setting and why the last process
 * ended. The channel exists only while this activity is attached.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingNotificationRequest: MethodChannel.Result? = null

    override fun getCachedEngineId(): String = TrippingApplication.ENGINE_ID

    // The engine outlives this activity: the journey keeps its recorder.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tripping/system").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "notificationsEnabled" -> result.success(notificationsEnabled())
                    "requestNotifications" -> requestNotifications(result)
                    "backgroundRestricted" -> result.success(backgroundRestricted())
                    "recentExits" -> result.success(recentExits())
                    "openAppSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.fromParts("package", packageName, null))
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingNotificationRequest?.success(notificationsEnabled())
        pendingNotificationRequest = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // geolocator uses its own request code through the same callback.
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATIONS_REQUEST) {
            pendingNotificationRequest?.success(notificationsEnabled())
            pendingNotificationRequest = null
        }
    }

    private fun notificationsEnabled(): Boolean =
        getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    /** Prompts at most as often as Android allows; never loops. */
    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(notificationsEnabled())
            return
        }
        if (pendingNotificationRequest != null) {
            result.error("busy", "A notification request is already showing", null)
            return
        }
        pendingNotificationRequest = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATIONS_REQUEST)
    }

    /** True when the user set battery use to Restricted: Android then stops
     *  the recording service as soon as Tripping leaves the screen. */
    private fun backgroundRestricted(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            getSystemService(ActivityManager::class.java).isBackgroundRestricted

    /** Why recent processes ended, newest first, as Android recorded it
     *  (API 30+). Dart picks the one that ended a recording. */
    private fun recentExits(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return getSystemService(ActivityManager::class.java)
            .getHistoricalProcessExitReasons(packageName, 0, RECENT_EXITS)
            .map { mapOf("cause" to causeOf(it), "at" to it.timestamp) }
    }

    private fun causeOf(exit: ApplicationExitInfo): String =
        when (exit.reason) {
            ApplicationExitInfo.REASON_USER_REQUESTED ->
                // A swipe from recents arrives as "[REMOVE TASK] remove task"
                // (seen on a Pixel 9a, Android 17).
                if (exit.description?.contains("remove task", ignoreCase = true) == true) {
                    "swiped"
                } else {
                    "user"
                }
            ApplicationExitInfo.REASON_USER_STOPPED -> "user"
            ApplicationExitInfo.REASON_CRASH,
            ApplicationExitInfo.REASON_CRASH_NATIVE,
            ApplicationExitInfo.REASON_ANR,
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "crash"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "memory"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission"
            ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE,
            PACKAGE_UPDATED -> "update"
            ApplicationExitInfo.REASON_OTHER ->
                // Android 17 reports its memory limiter this way.
                if (exit.description?.contains("MemoryLimiter") == true) "memory" else "system"
            else -> "system"
        }

    companion object {
        // Any code other than geolocator's (109).
        private const val NOTIFICATIONS_REQUEST = 4207

        // ApplicationExitInfo.REASON_PACKAGE_UPDATED (API 34).
        private const val PACKAGE_UPDATED = 16

        private const val RECENT_EXITS = 16
    }
}
