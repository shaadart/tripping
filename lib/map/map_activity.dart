import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// MapLibre Native's supported connectivity override. Stops tile retries
/// while paused/backgrounded, without preventing cached map interaction.
abstract final class MapActivity {
  static const _channel = MethodChannel('tripping/map_activity');

  static Future<void> setNetworkEnabled(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('setNetworkEnabled', enabled);
  }
}
