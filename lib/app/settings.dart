import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The few preferences Tripping keeps, in a small JSON file next to the
/// journeys. Never location data.
class Settings {
  Settings._(this._file, bool highSun) : highSun = ValueNotifier(highSun);

  /// Reads [file]; a missing or unreadable file means the defaults.
  static Future<Settings> open(File file) async {
    var highSun = false;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map && json['highSun'] is bool) {
        highSun = json['highSun'] as bool;
      }
    } on Object {
      // Defaults: a preference is never worth failing to start over.
    }
    return Settings._(file, highSun);
  }

  final File _file;

  /// The high-contrast look for bright daylight, whatever the system theme.
  final ValueNotifier<bool> highSun;

  Future<void> setHighSun(bool on) async {
    highSun.value = on;
    // Written beside and renamed over, so a crash never leaves half a file.
    final next = File('${_file.path}.next');
    await next.writeAsString(jsonEncode({'highSun': on}), flush: true);
    await next.rename(_file.path);
  }
}
