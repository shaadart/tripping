import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;

import '../history/journey_history.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../map/track_geometry.dart';

/// R6: long journeys measured on a device.
///
/// Only compiled in with `--dart-define=TRIPPING_BENCH=true`, which also
/// points the app at [databaseName], so the owner's journeys are never
/// touched. The data is synthetic, around a public place. Logs timings and
/// counts, never positions.
abstract final class LongJourneyBench {
  static const enabled = bool.fromEnvironment('TRIPPING_BENCH');
  static const databaseName = 'bench.sqlite';

  /// A day of driving at one fix a second.
  static const _driveHours = 24;
  static const _walks = 99;

  /// Seeds the bench database once, then measures what opening long
  /// journeys costs.
  static Future<void> run(JourneyStore store, File file) async {
    if ((await store.endedJourneys()).isEmpty) await _seed(store);
    await _measure(store, file);
  }

  /// Logs how long a past journey's map took to draw.
  static void detailDrawn(Duration sinceCreated) =>
      _log('detail_map_drawn ms=${sinceCreated.inMilliseconds}');

  static Future<void> _seed(JourneyStore store) async {
    final now = DateTime.now().toUtc();
    // Short walks, bulk-inserted: they exist to fill the list.
    for (var i = 0; i < _walks; i++) {
      final start = now.subtract(Duration(days: _walks + 2 - i));
      final journey = await store.startJourney(
        JourneyMode.expedition,
        at: start,
      );
      final fixes = _trace(seed: i, start: start, seconds: 1800, speed: 1.4);
      await store.batch(
        (batch) => batch.insertAll(store.trackPoints, [
          for (final fix in fixes)
            TrackPointsCompanion.insert(
              journeyId: journey.id,
              time: fix.time,
              segment: 0,
              latitude: fix.latitude,
              longitude: fix.longitude,
              accuracy: Value(fix.accuracy),
              altitude: Value(fix.altitude),
              altitudeAccuracy: Value(fix.altitudeAccuracy),
              speed: Value(fix.speed),
              heading: Value(fix.heading),
            ),
        ]),
      );
      await store.end(journey.id, at: fixes.last.time);
    }
    _log('seeded walks=$_walks fixes_each=1800');

    // The long drive goes through the app's own append, one fix at a time,
    // so its latency is measured as the journey grows.
    final start = now.subtract(const Duration(days: 1, hours: 1));
    final drive = await store.startJourney(JourneyMode.road, at: start);
    final fixes = _trace(
      seed: 1000,
      start: start,
      seconds: _driveHours * 3600,
      speed: 15,
    );
    final micros = <int>[];
    final clock = Stopwatch();
    for (final (i, fix) in fixes.indexed) {
      clock
        ..reset()
        ..start();
      await store.append(drive.id, fix);
      micros.add(clock.elapsedMicroseconds);
      if ((i + 1) % 21600 == 0) {
        _log('append upto=${i + 1} ${_percentiles(micros, 'us')}');
        micros.clear();
      }
    }
    await store.end(drive.id, at: fixes.last.time);
    _log('seeded drive fixes=${fixes.length}');
  }

  static Future<void> _measure(JourneyStore store, File file) async {
    final clock = Stopwatch()..start();
    Duration lap() {
      final elapsed = clock.elapsed;
      clock
        ..reset()
        ..start();
      return elapsed;
    }

    final history = JourneyHistory(store);
    final past = await history.load();
    _log('history_load journeys=${past.length} ms=${lap().inMilliseconds}');
    final drive = past.firstWhere((p) => p.journey.mode == JourneyMode.road);

    final track = await store.track(drive.journey.id);
    final fixes = track.fold(0, (sum, s) => sum + s.length);
    _log('store_track fixes=$fixes ms=${lap().inMilliseconds}');

    final drawn = await history.trackOf(drive.journey.id);
    final points = drawn.fold(0, (sum, s) => sum + s.length);
    _log('detail_track points=$points ms=${lap().inMilliseconds}');

    final json = jsonEncode(trackFeatures(drawn));
    _log('detail_geojson bytes=${json.length} ms=${lap().inMilliseconds}');

    final buffer = TrackBuffer()..reset(track);
    final kept = buffer.history.fold(0, (sum, s) => sum + s.length);
    _log('live_reset history_points=$kept ms=${lap().inMilliseconds}');

    final gpx = await history.gpxOf(drive, name: 'bench');
    _log('gpx bytes=${gpx.length} ms=${lap().inMilliseconds}');

    final bytes = [
      file,
      File('${file.path}-wal'),
    ].where((f) => f.existsSync()).fold(0, (sum, f) => sum + f.lengthSync());
    _log(
      'database bytes=$bytes per_fix='
      '${(bytes / (fixes + _walks * 1800)).toStringAsFixed(1)}',
    );
  }

  /// A synthetic trace from a public place (Cubbon Park): gently wandering
  /// heading, a two-minute stop every half hour, a hill (walks) or rolling
  /// ground (the drive), and GPS error that drifts like the real thing
  /// (Gauss–Markov, 30 s).
  static List<Fix> _trace({
    required int seed,
    required DateTime start,
    required int seconds,
    required double speed,
  }) {
    const earthRadius = 6371008.8;
    final random = Random(seed);
    double gaussian() =>
        sqrt(-2 * log(1 - random.nextDouble())) *
        cos(2 * pi * random.nextDouble());
    const sigma = 5 / 1.51;
    final keep = exp(-1 / 30);
    final fresh = sigma * sqrt(1 - keep * keep);
    var latitude = 12.9763 + seed * 1e-4;
    var longitude = 77.5929;
    var heading = random.nextDouble() * 2 * pi;
    var errorEast = sigma * gaussian(), errorNorth = sigma * gaussian();
    // Height: a hill on each walk, rolling ground on the drive, with GPS
    // height error that wanders like the real thing.
    const verticalSigma = 4.0;
    final verticalFresh = verticalSigma * sqrt(1 - keep * keep);
    var errorUp = verticalSigma * gaussian();
    double ground(int s) => speed < 5
        ? 900 + 80 * (1 - (2 * s / seconds - 1).abs())
        : 900 + 150 * sin(2 * pi * s / 7200);
    return [
      for (var s = 0; s < seconds; s++)
        () {
          final moving = s % 1800 >= 120;
          final v = moving ? speed : 0.0;
          heading += gaussian() * 0.03;
          latitude += v * cos(heading) / earthRadius * 180 / pi;
          longitude +=
              v *
              sin(heading) /
              (earthRadius * cos(latitude * pi / 180)) *
              180 /
              pi;
          errorEast = keep * errorEast + fresh * gaussian();
          errorNorth = keep * errorNorth + fresh * gaussian();
          errorUp = keep * errorUp + verticalFresh * gaussian();
          return Fix(
            time: start.add(Duration(seconds: s)),
            latitude: latitude + errorNorth / earthRadius * 180 / pi,
            longitude:
                longitude +
                errorEast / (earthRadius * cos(latitude * pi / 180)) * 180 / pi,
            accuracy: 5,
            altitude: ground(s) + errorUp + gaussian(),
            altitudeAccuracy: verticalSigma,
            speed: max(0, v + gaussian() * 0.1),
            heading: (heading * 180 / pi) % 360,
          );
        }(),
    ];
  }

  static String _percentiles(List<int> values, String unit) {
    final sorted = [...values]..sort();
    int at(double p) =>
        sorted[min(sorted.length - 1, (p * sorted.length).floor())];
    return 'p50=${at(.5)} p95=${at(.95)} p99=${at(.99)} max=${sorted.last} $unit';
  }

  // ignore: avoid_print
  static void _log(String line) => print('BENCH $line');
}
