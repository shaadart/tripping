package com.example.tripping

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

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
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "tripping"
    }
}
