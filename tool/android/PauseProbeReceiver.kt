package com.shaadart.tripping

// Copied ONLY into the isolated probe APK, never the production application.
// Reports this synthetic app's metadata/counters, without coordinates/keys.
import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.net.TrafficStats
import android.os.Process
import android.os.Handler
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class PauseProbeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val command = intent.getStringExtra("command") ?: "sample"
        if (command == "sample") {
            val result = JSONObject()
                .put("pid", Process.myPid())
                .put("cpuMs", Process.getElapsedCpuTime())
                .put("rxBytes", TrafficStats.getUidRxBytes(Process.myUid()))
                .put("txBytes", TrafficStats.getUidTxBytes(Process.myUid()))
            @Suppress("DEPRECATION")
            val services = context.getSystemService(ActivityManager::class.java)
                .getRunningServices(50).filter { it.uid == Process.myUid() }
            result.put("foregroundServices", services.count { it.foreground })
            val apps = FirebaseApp.getApps(context)
            val liveAuth = apps.firstOrNull { it.name == FirebaseApp.DEFAULT_APP_NAME }
                ?.let { FirebaseAuth.getInstance(it) }
            val parkedAuth = apps.firstOrNull { it.name == "tripping-paused-identity-v1" }
                ?.let { FirebaseAuth.getInstance(it) }
            val live = liveAuth?.currentUser
            val parked = parkedAuth?.currentUser
            result.put("transportAuthenticated", live != null)
            result.put("parkedIdentity", parked != null)
            result.put("sameIdentity", live != null && live.uid == parked?.uid)
            result.put("transportRefreshPending", refreshPending(liveAuth))
            result.put("holdingRefreshPending", refreshPending(parkedAuth))
            val file = File(context.dataDir, "app_flutter/journeys.sqlite")
            if (file.exists()) {
                SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                    db.rawQuery("SELECT id,uuid,status FROM journeys ORDER BY id DESC LIMIT 1", null).use { row ->
                        if (row.moveToFirst()) {
                            result.put("journey", row.getLong(0))
                            result.put("uuid", row.getString(1))
                            result.put("status", row.getString(2))
                            db.rawQuery("SELECT count(*) FROM track_points WHERE journey_id=?", arrayOf(row.getString(0))).use {
                                it.moveToFirst(); result.put("fixes", it.getInt(0))
                            }
                            db.rawQuery("SELECT count(*) FROM segments WHERE journey_id=?", arrayOf(row.getString(0))).use {
                                it.moveToFirst(); result.put("segments", it.getInt(0))
                            }
                        }
                    }
                }
            }
            resultData = result.toString()
            return
        }
        val engine = FlutterEngineCache.getInstance().get("tripping")
        if (engine == null) { resultData = "engine-not-ready"; return }
        val pending = goAsync()
        MethodChannel(engine.dartExecutor.binaryMessenger, "tripping/pause_probe")
            .invokeMethod(command, null, object : MethodChannel.Result {
                override fun success(result: Any?) { pending.resultData = "done"; pending.finish() }
                override fun error(code: String, message: String?, details: Any?) {
                    pending.resultData = "failed:$code"; pending.finish()
                }
                override fun notImplemented() { pending.resultData = "not-ready"; pending.finish() }
            })
    }

    // Diagnostics ONLY for the pinned Auth 25.0.0 test SDK. Production uses
    // public APIs exclusively. Null means SDK layout changed: evidence unknown.
    private fun refreshPending(auth: FirebaseAuth?): Any {
        if (auth == null) return false
        return try {
            fun field(owner: Any, name: String): Any? {
                var type: Class<*>? = owner.javaClass
                while (type != null) {
                    try { return type.getDeclaredField(name).apply { isAccessible = true }.get(owner) }
                    catch (_: NoSuchFieldException) { type = type.superclass }
                }
                throw NoSuchFieldException(name)
            }
            val manager = field(auth, "zzy") ?: return false
            val refresher = field(manager, "zzb") ?: return JSONObject.NULL
            val handler = field(refresher, "zzd") as Handler
            handler.hasCallbacks(field(refresher, "zze") as Runnable)
        } catch (_: Exception) { JSONObject.NULL }
    }
}
