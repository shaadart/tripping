package com.example.tripping

import io.flutter.embedding.android.FlutterActivity

/** Shows the process-wide engine owned by [TrippingApplication]. */
class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String = TrippingApplication.ENGINE_ID

    // The engine outlives this activity: the journey keeps its recorder.
    override fun shouldDestroyEngineWithHost(): Boolean = false
}
