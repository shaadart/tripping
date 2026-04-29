import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../group/invite.dart';

/// The few preferences Tripping keeps, in a small JSON file next to the
/// journeys, with this install's identity in groups. Never location data.
class Settings {
  Settings._(
    this._file, {
    required bool highSun,
    String? tileRelease,
    String? participantId,
    String? name,
  }) : highSun = ValueNotifier(highSun),
       tileRelease = ValueNotifier(tileRelease),
       _participantId = participantId,
       name = ValueNotifier(name);

  /// Reads [file]; a missing or unreadable file means the defaults.
  static Future<Settings> open(File file) async {
    var highSun = false;
    String? tileRelease;
    String? participantId;
    String? name;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map) {
        if (json['highSun'] is bool) highSun = json['highSun'] as bool;
        if (json['tileRelease'] is String) {
          tileRelease = json['tileRelease'] as String;
        }
        if (json['participantId'] case final String id
            when Invite.isSecret(id)) {
          participantId = id;
        }
        if (json['name'] case final String saved
            when Invite.cleanName(saved).isNotEmpty) {
          name = Invite.cleanName(saved);
        }
      }
    } on Object {
      // Defaults: a preference is never worth failing to start over.
    }
    return Settings._(
      file,
      highSun: highSun,
      tileRelease: tileRelease,
      participantId: participantId,
      name: name,
    );
  }

  final File _file;

  /// The high-contrast look for bright daylight, whatever the system theme.
  final ValueNotifier<bool> highSun;

  /// The map tile release drawn and downloaded from (see `MapTiles`).
  final ValueNotifier<String?> tileRelease;

  /// How this phone's user appears to companions; asked once, on first
  /// inviting or joining.
  final ValueNotifier<String?> name;

  String? _participantId;

  /// This install in every group: 128 random bits, made on first need and
  /// kept. Not tied to the phone, an account or a number.
  Future<String> participantId() async {
    final id = _participantId;
    if (id != null) return id;
    final made = _participantId = newSecret();
    await _save();
    return made;
  }

  Future<void> setName(String value) async {
    name.value = Invite.cleanName(value);
    await _save();
  }

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
      jsonEncode({
        'highSun': highSun.value,
        'tileRelease': ?tileRelease.value,
        'participantId': ?_participantId,
        'name': ?name.value,
      }),
      flush: true,
    );
    await next.rename(_file.path);
  }
}
