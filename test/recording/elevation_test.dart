import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/elevation.dart';
import 'package:tripping/recording/track_policy.dart';
import 'package:tripping/recording/track_stats.dart';

final t0 = DateTime.utc(2026, 10, 28, 6);

/// One fix a second along [height] (metres at second s), with GPS altitude
/// error that wanders (Gauss–Markov, 60 s) plus jitter, and the stated
/// vertical accuracy equal to the error's spread.
List<Fix> climbTrace(
  double Function(int second) height, {
  required int seed,
  int seconds = 3600,
  double sigma = 5,
}) {
  final random = Random(seed);
  double gaussian() =>
      sqrt(-2 * log(1 - random.nextDouble())) *
      cos(2 * pi * random.nextDouble());
  final keep = exp(-1 / 60);
  final fresh = sigma * sqrt(1 - keep * keep);
  var error = sigma * gaussian();
  return [
    for (var s = 0; s < seconds; s++)
      () {
        error = keep * error + fresh * gaussian();
        return Fix(
          time: t0.add(Duration(seconds: s)),
          latitude: 32 + s * 1e-5,
          longitude: 77,
          accuracy: 5,
          altitude: height(s) + error + 1.5 * gaussian(),
          altitudeAccuracy: sigma,
        );
      }(),
  ];
}

(double, double) count(List<Fix> fixes) {
  final counter = ElevationCounter();
  fixes.forEach(counter.add);
  return (counter.climb!, counter.descent!);
}

void main() {
  const seeds = 20;

  test('standing on flat ground for an hour adds almost no climb', () {
    final climbs = [
      for (var seed = 0; seed < seeds; seed++)
        count(climbTrace((_) => 2000, seed: seed)).$1,
    ];
    // At most about one band (5 × 5 m) in a rare hour.
    expect(climbs.reduce(max), lessThan(60));
    expect(climbs.reduce((a, b) => a + b) / seeds, lessThan(10));
  });

  test('a steady 300 m climb counts within 10 %', () {
    for (var seed = 0; seed < seeds; seed++) {
      final (climb, descent) = count(
        climbTrace((s) => 2000 + 300 * s / 3600, seed: seed),
      );
      expect(climb, inInclusiveRange(270, 330), reason: 'seed $seed');
      expect(descent, lessThan(30), reason: 'seed $seed');
    }
  });

  test('up and down a 100 m hill counts both ways', () {
    double hill(int s) => 2000 + 100 * (1 - (2 * s / 3600 - 1).abs());
    var climbs = 0.0, descents = 0.0;
    for (var seed = 0; seed < seeds; seed++) {
      final (climb, descent) = count(climbTrace(hill, seed: seed));
      expect(climb, inInclusiveRange(75, 125), reason: 'seed $seed');
      expect(descent, inInclusiveRange(75, 125), reason: 'seed $seed');
      climbs += climb;
      descents += descent;
    }
    expect(climbs / seeds, closeTo(100, 10));
    expect(descents / seeds, closeTo(100, 10));
  });

  test('noisier altitude widens the band instead of inventing climb', () {
    final climbs = [
      for (var seed = 0; seed < seeds; seed++)
        count(climbTrace((_) => 2000, seed: seed, sigma: 12)).$1,
    ];
    expect(climbs.reduce((a, b) => a + b) / seeds, lessThan(20));
  });

  test('without a stated vertical accuracy the climb is unknown, not 0', () {
    final counter = ElevationCounter()
      ..add(Fix(time: t0, latitude: 32, longitude: 77, altitude: 2000));
    expect(counter.climb, isNull);
    expect(counter.descent, isNull);
  });

  test('too vague an altitude is ignored', () {
    final counter = ElevationCounter();
    for (var s = 0; s < 100; s++) {
      counter.add(
        Fix(
          time: t0.add(Duration(seconds: s)),
          latitude: 32,
          longitude: 77,
          altitude: s * 10.0,
          altitudeAccuracy: ElevationCounter.maxVerticalAccuracy + 1,
        ),
      );
    }
    expect(counter.climb, isNull);
  });

  test('nothing is counted across a gap between segments', () {
    final policy = TrackPolicy.of(JourneyMode.expedition);
    final low = climbTrace((_) => 1000, seed: 1, seconds: 300);
    final high = [
      for (final fix in climbTrace((_) => 1500, seed: 2, seconds: 300))
        Fix(
          time: fix.time.add(const Duration(hours: 1)),
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracy: fix.accuracy,
          altitude: fix.altitude,
          altitudeAccuracy: fix.altitudeAccuracy,
        ),
    ];
    final stats = TrackStats.replay(policy, [low, high]);
    expect(stats.elevation.climb, lessThan(25));
  });

  test('replaying a track reproduces the live count', () {
    final policy = TrackPolicy.of(JourneyMode.expedition);
    final fixes = climbTrace((s) => 2000 + 200 * s / 3600, seed: 9);
    final live = TrackStats(policy)..startSegment();
    fixes.forEach(live.add);
    final replayed = TrackStats.replay(policy, [fixes]);
    expect(replayed.elevation.climb, live.elevation.climb);
    expect(replayed.elevation.descent, live.elevation.descent);
  });
}
