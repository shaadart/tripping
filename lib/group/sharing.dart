import '../journey/geo.dart';
import '../journey/journey.dart';

/// Where this phone's journey stands, as the group sees it.
enum JourneyPhase { recording, paused, ended }

/// What this phone tells its group (G3, D-037): its name, its journey's
/// phase and mode, and the newest fix the phone has saved. Never a fix that
/// was not saved first.
class Shared {
  const Shared({
    required this.name,
    required this.phase,
    required this.mode,
    this.fix,
  });

  final String name;
  final JourneyPhase phase;
  final JourneyMode mode;
  final Fix? fix;

  /// The message before sealing: short keys, about 1 m of precision, under
  /// 200 bytes even with a 40-character name.
  Map<String, Object?> toMessage() => {
    'n': name,
    's': phase.name[0],
    'm': mode.name[0],
    if (fix case final fix?)
      'p': [
        _round(fix.latitude),
        _round(fix.longitude),
        (fix.accuracy ?? 0).round(),
        fix.time.millisecondsSinceEpoch ~/ 1000,
      ],
  };

  /// A companion's message, or null when it is not one: damaged, or from a
  /// version that says too little.
  static Shared? fromMessage(Map<String, Object?> message) {
    final name = message['n'];
    final phase = switch (message['s']) {
      'r' => JourneyPhase.recording,
      'p' => JourneyPhase.paused,
      'e' => JourneyPhase.ended,
      _ => null,
    };
    final mode = switch (message['m']) {
      'r' => JourneyMode.road,
      'e' => JourneyMode.expedition,
      _ => null,
    };
    if (name is! String || phase == null || mode == null) return null;
    Fix? fix;
    if (message['p'] case [
      final num lat,
      final num lon,
      final num accuracy,
      final num seconds,
    ] when lat.abs() <= 90 && lon.abs() <= 180) {
      fix = Fix(
        time: DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000,
          isUtc: true,
        ),
        latitude: lat.toDouble(),
        longitude: lon.toDouble(),
        accuracy: accuracy.toDouble(),
      );
    }
    return Shared(name: name, phase: phase, mode: mode, fix: fix);
  }

  static double _round(double degrees) =>
      (degrees * 100000).roundToDouble() / 100000;
}

/// How often a mode tells the group where it is: whichever comes first of
/// [every] and [moved], never closer together than [atLeast] (the relay
/// refuses faster writes).
class SharePolicy {
  const SharePolicy({required this.every, required this.moved});

  static const road = SharePolicy(every: Duration(seconds: 10), moved: 100);
  static const expedition = SharePolicy(
    every: Duration(seconds: 30),
    moved: 50,
  );

  static SharePolicy of(JourneyMode mode) => switch (mode) {
    JourneyMode.road => road,
    JourneyMode.expedition => expedition,
  };

  static const atLeast = Duration(milliseconds: 2500);

  final Duration every;
  final double moved;

  /// Whether [now] is worth telling, given [told] at [toldAt]. A new phase
  /// (start, pause, end) is told at once.
  bool due(Shared now, Shared? told, DateTime toldAt, DateTime at) {
    if (told == null) return true;
    final since = at.difference(toldAt);
    if (since < atLeast) return false;
    if (now.phase != told.phase) return true;
    if (since >= every) return true;
    final (a, b) = (now.fix, told.fix);
    if (a == null || b == null) return a != b;
    return a.metersTo(b) >= moved;
  }
}

/// How current a companion's position is, by its age and their mode.
enum Freshness { live, aging, stale }

Freshness freshnessOf(Duration age, JourneyMode mode) {
  final every = SharePolicy.of(mode).every;
  if (age <= every * 2 + const Duration(seconds: 5)) return Freshness.live;
  if (age <= const Duration(minutes: 5)) return Freshness.aging;
  return Freshness.stale;
}

/// "1.2 km NE" from [here] to [there]; "here" within 20 m.
String distanceAndDirection(Fix here, Fix there) {
  final meters = here.metersTo(there);
  if (meters < 20) return 'here';
  // Rounded first, so 999.8 m reads "1.0 km", not "1000 m".
  final tens = (meters / 10).round() * 10;
  final distance = tens < 1000
      ? '$tens m'
      : '${(meters / 1000).toStringAsFixed(meters < 9950 ? 1 : 0)} km';
  return '$distance ${compassPoint(here.bearingTo(there))}';
}
