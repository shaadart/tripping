import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../group/invite.dart';
import '../group/identity.dart';

/// The few preferences Tripping keeps, in a small JSON file next to the
/// journeys, with this install's identity in groups. Never location data.
class Settings {
  Settings._(
    this._file, {
    required bool highSun,
    String? tileRelease,
    String? participantId,
    String? name,
    IdentityColour colour = IdentityColour.clay,
    MarkerShape shape = MarkerShape.tablet,
    bool identityReady = false,
    Set<String> sharingPaused = const {},
  }) : highSun = ValueNotifier(highSun),
       tileRelease = ValueNotifier(tileRelease),
       _participantId = participantId,
       name = ValueNotifier(name),
       identity = ValueNotifier(
         MapIdentity(name: name ?? 'Traveller', colour: colour, shape: shape),
       ),
       _savedIdentity = MapIdentity(
         name: name ?? 'Traveller',
         colour: colour,
         shape: shape,
       ),
       _identityReady = identityReady,
       _sharingPaused = sharingPaused;

  /// Reads [file]; a missing or unreadable file means the defaults.
  static Future<Settings> open(File file) async {
    var highSun = false;
    String? tileRelease;
    String? participantId;
    String? name;
    var colour = IdentityColour.clay;
    var shape = MarkerShape.tablet;
    bool? identityReady;
    var sharingPaused = <String>{};
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map) {
        colour = IdentityColour.parse(json['identityColour']);
        shape = MarkerShape.parse(json['identityShape']);
        if (json['identityReady'] is bool) {
          identityReady = json['identityReady'] as bool;
        }
        if (json['sharingPaused'] case final List<Object?> paused) {
          sharingPaused = paused.whereType<String>().toSet();
        }
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
      colour: colour,
      shape: shape,
      identityReady: identityReady ?? name != null,
      sharingPaused: sharingPaused,
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
  final ValueNotifier<MapIdentity> identity;
  MapIdentity _savedIdentity;
  bool _identityReady;
  bool get identityReady => _identityReady;

  String? _participantId;
  final Set<String> _sharingPaused;
  Future<void> _writes = Future.value();

  bool sharingPaused(String journey) => _sharingPaused.contains(journey);

  /// A sharing-only pause survives reopening and does not pause recording.
  Future<void> setSharingPaused(String journey, bool paused) async {
    if (paused) {
      _sharingPaused.add(journey);
    } else {
      _sharingPaused.remove(journey);
    }
    await _save();
  }

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
    await setIdentity(
      MapIdentity(
        name: value,
        colour: identity.value.colour,
        shape: identity.value.shape,
      ),
    );
  }

  Future<void> setIdentity(MapIdentity value) async {
    final clean = MapIdentity(
      name: value.displayName,
      colour: value.colour,
      shape: value.shape,
    );
    await _save(identityOverride: clean);
    name.value = clean.name;
    identity.value = clean;
  }

  Future<void> setHighSun(bool on) async {
    highSun.value = on;
    await _save();
  }

  Future<void> setTileRelease(String release) async {
    tileRelease.value = release;
    await _save();
  }

  Future<void> _save({MapIdentity? identityOverride}) {
    final result = _writes.then((_) => _write(identityOverride));
    _writes = result.catchError((Object _) {});
    return result;
  }

  Future<void> _write(MapIdentity? identityOverride) async {
    // Written beside and renamed over, so a crash never leaves half a file.
    final next = File('${_file.path}.next');
    await next.writeAsString(
      jsonEncode({
        'highSun': highSun.value,
        if (_sharingPaused.isNotEmpty) 'sharingPaused': _sharingPaused.toList(),
        'tileRelease': ?tileRelease.value,
        'participantId': ?_participantId,
        if (identityOverride != null || name.value != null || _identityReady)
          'name': (identityOverride ?? _savedIdentity).name,
        'identityColour': (identityOverride ?? _savedIdentity).colour.name,
        'identityShape': (identityOverride ?? _savedIdentity).shape.name,
        'identityReady': identityOverride != null || _identityReady,
      }),
      flush: true,
    );
    await next.rename(_file.path);
    if (identityOverride != null) {
      _savedIdentity = identityOverride;
      _identityReady = true;
    }
  }
}
