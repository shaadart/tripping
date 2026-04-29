package com.shaadart.tripping

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.maplibre.android.MapLibre

/**
 * Owns the one Flutter engine of the process, so Dart's main() runs exactly
 * once per process however many times the activity is created or destroyed.
 *
 * With Flutter's default (an engine per activity) a relaunch can start a
 * second engine beside the first: two openers of the journey database and
 * two recorders. It would also stop recording whenever the activity goes
 * away, even while a foreground service keeps the process alive.
 */
class TrippingApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        GroupAuth(this, engine.dartExecutor.binaryMessenger)
        // Start disconnected until Dart has restored durable journey state.
        // This channel outlives activities, like the recorder's engine.
        MapLibre.getInstance(this)
        MapLibre.setConnected(false)
        MethodChannel(engine.dartExecutor.binaryMessenger, "tripping/map_activity")
            .setMethodCallHandler { call, result ->
                if (call.method == "setNetworkEnabled") {
                    MapLibre.setConnected(call.arguments as Boolean)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "tripping"
    }
}
