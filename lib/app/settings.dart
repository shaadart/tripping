import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The few preferences Tripping keeps, in a small JSON file next to the
/// journeys. Never location data.
class Settings {
  Settings._(this._file, {required bool highSun, String? tileRelease})
    : highSun = ValueNotifier(highSun),
      tileRelease = ValueNotifier(tileRelease);

  /// Reads [file]; a missing or unreadable file means the defaults.
  static Future<Settings> open(File file) async {
    var highSun = false;
    String? tileRelease;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map) {
        if (json['highSun'] is bool) highSun = json['highSun'] as bool;
        if (json['tileRelease'] is String) {
          tileRelease = json['tileRelease'] as String;
        }
      }
    } on Object {
      // Defaults: a preference is never worth failing to start over.
    }
    return Settings._(file, highSun: highSun, tileRelease: tileRelease);
  }

  final File _file;

  /// The high-contrast look for bright daylight, whatever the system theme.
  final ValueNotifier<bool> highSun;

  /// The map tile release drawn and downloaded from (see `MapTiles`).
  final ValueNotifier<String?> tileRelease;

  Future<void> setHighSun(bool on) async {
    highSun.value = on;
    await _save();
  }

  Future<void> setTileRelease(String release) async {
    tileRelease.value = release;
    await _save();
  }

  Future<void> _save() async {
    // Written beside and renamed over, so a crash never leaves half a file.
    final next = File('${_file.path}.next');
    await next.writeAsString(
      jsonEncode({'highSun': highSun.value, 'tileRelease': ?tileRelease.value}),
      flush: true,
    );
    await next.rename(_file.path);
  }
}
