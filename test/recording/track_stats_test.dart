import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/fix_filter.dart';
import 'package:tripping/recording/track_policy.dart';
import 'package:tripping/recording/track_stats.dart';

import '../support/traces.dart';

const seeds = 25;
const minute = Duration(minutes: 1);

/// Runs fixes through the filter into stats, as the recorder will.
TrackStats measure(TrackPolicy policy, Iterable<Fix> fixes) {
  final filter = FixFilter(policy);
  final stats = TrackStats(policy);
  for (final fix in fixes) {
    if (filter.judge(fix).belongsInTrack) stats.add(fix);
  }
  return stats;
}

typedef Run = ({double counted, double truth});

/// Builds the same scenario for every seed and measures it.
List<Run> runSeeds(
  TrackPolicy policy, {
  required double accuracy,
  bool reportsSpeed = true,
  required void Function(TraceBuilder trace) build,
}) => [
  for (var seed = 0; seed < seeds; seed++)
    () {
      final trace = TraceBuilder(
        seed: seed,
        accuracy: accuracy,
        reportsSpeed: reportsSpeed,
      );
      build(trace);
      return (
        counted: measure(policy, trace.fixes).meters,
        truth: trace.trueMeters,
      );
    }(),
];

/// Every seed's count is within [fraction] of what was truly covered, plus
/// [slack] metres. On short trips the slack is one gate: the total trails
/// the truth by up to that much by design (see TrackStats).
void expectWithin(
  String scenario,
  List<Run> runs,
  double fraction, {
  double slack = 0,
}) {
  final errors = [for (final run in runs) run.counted / run.truth - 1];
  report(scenario, errors.map((e) => e * 100), unit: '%');
  for (var seed = 0; seed < runs.length; seed++) {
    expect(
      runs[seed].counted,
      closeTo(runs[seed].truth, runs[seed].truth * fraction + slack),
      reason: '$scenario, seed $seed',
    );
  }
}

/// Set TRACE_REPORT=1 to print each scenario's spread across seeds.
void report(String scenario, Iterable<double> values, {String unit = ' m'}) {
  if (!Platform.environment.containsKey('TRACE_REPORT')) return;
  final sorted = [...values]..sort();
  debugPrint(
    'TRACE $scenario: ${sorted.first.toStringAsFixed(2)}$unit .. '
    '${sorted.last.toStringAsFixed(2)}$unit over ${sorted.length} seeds',
  );
}

void standStill(TraceBuilder trace) => trace
  ..stay(minute * 10)
  ..outlier(300)
  ..stay(minute * 10)
  ..outlier(-300)
  ..stay(minute * 10);

void main() {
  group('standing still for 30 min at ±25 m with two 300 m outliers', () {
    for (final (mode, policy) in [
      ('expedition', TrackPolicy.expedition),
      ('road', TrackPolicy.road),
    ]) {
      test('adds less than 30 m when the phone reports speed ($mode)', () {
        final runs = runSeeds(policy, accuracy: 25, build: standStill);

        final counted = [for (final run in runs) run.counted];
        report('still-$mode', counted);
        expect(counted, everyElement(lessThan(30)));
      });
    }

    test('without reported speed, rarely adds one gate of drift', () {
      // Positions alone cannot tell error wandering at walking pace from
      // walking. This pins down the residual risk instead of hiding it.
      final runs = runSeeds(
        TrackPolicy.expedition,
        accuracy: 25,
        reportsSpeed: false,
        build: standStill,
      );

      final counted = [for (final run in runs) run.counted];
      report('still-position-only', counted);
      final gate = TrackPolicy.expedition.gateFactor * 25;
      expect(counted.where((m) => m >= 30).length, lessThanOrEqualTo(2));
      expect(counted, everyElement(lessThan(2 * gate)));
    });
  });

  for (final reportsSpeed in [true, false]) {
    final source = reportsSpeed ? 'with speed' : 'position only';

    test('a slow 1 km walk at 0.5 m/s and ±8 m is within 3 % ($source)', () {
      final runs = runSeeds(
        TrackPolicy.expedition,
        accuracy: 8,
        reportsSpeed: reportsSpeed,
        build: (trace) =>
            trace.move(duration: const Duration(seconds: 2000), speed: 0.5),
      );

      expectWithin('walk-1km ($source)', runs, 0.03);
    });

    test('a 10 km drive at 25 m/s and ±5 m is within 1 % ($source)', () {
      final runs = runSeeds(
        TrackPolicy.road,
        accuracy: 5,
        reportsSpeed: reportsSpeed,
        build: (trace) => trace.move(
          duration: const Duration(seconds: 400),
          speed: 25,
          heading: 90,
        ),
      );

      expectWithin('drive-10km ($source)', runs, 0.01);
    });
  }

  group('signal gaps and jumps', () {
    test('a 2 min gap followed by a plausible position is counted', () {
      final runs = runSeeds(
        TrackPolicy.road,
        accuracy: 5,
        build: (trace) => trace
          ..move(duration: minute, speed: 25, heading: 90)
          ..gap(minute * 2, east: 1500)
          ..move(duration: minute, speed: 25, heading: 90),
      );

      expectWithin('tunnel-gap', runs, 0.01);
    });

    test('a single wild fix is ignored', () {
      final runs = runSeeds(
        TrackPolicy.road,
        accuracy: 5,
        build: (trace) => trace
          ..move(duration: minute, speed: 20, heading: 90)
          ..outlier(5000)
          ..move(duration: minute, speed: 20, heading: 90),
      );

      // Without the filter the wild fix would add 10 km.
      expectWithin(
        'wild-fix',
        runs,
        0.01,
        slack: TrackPolicy.road.gateFactor * 5,
      );
    });

    test('a confirmed relocation is followed, and the jump is not counted', () {
      final runs = runSeeds(
        TrackPolicy.road,
        accuracy: 5,
        build: (trace) => trace
          ..move(duration: minute, speed: 20, heading: 90)
          ..gap(const Duration(seconds: 10), north: 20000)
          ..move(duration: minute, speed: 20, heading: 90),
      );

      // 1,180 m observed before the jump; after it, counting restarts at the
      // relocated fix, the third one (2 × 20 m held back), leaving 1,140 m.
      // Each side may trail by one gate (20 m) and carries endpoint noise.
      // The 20 km jump never counts.
      final counted = [for (final run in runs) run.counted];
      report('relocation', counted);
      expect(counted, everyElement(inInclusiveRange(2250, 2340)));
    });
  });

  group('field-shaped cases (Pixel 9a, E-011)', () {
    test('a short walk while GPS warms up is counted', () {
      // As recorded after a resume: the first fix is ±21 m and accuracy
      // settles at ±8 m over 30 s, during a 70 m walk at 1.1 m/s. The
      // previous rule counted 0 m.
      final runs = runSeeds(
        TrackPolicy.expedition,
        accuracy: 21,
        build: (trace) {
          for (var second = 0; second < 64; second += 2) {
            trace.accuracy = second < 30 ? 21 - 13 * second / 30 : 8;
            trace.move(
              duration: const Duration(seconds: 2),
              interval: const Duration(seconds: 2),
              speed: 1.1,
            );
          }
        },
      );

      // A measurement that starts from a ±21 m fix inherits that uncertainty
      // once, and the total may trail by one moving gate (2 × 8 m). Beyond
      // that bound the rule would be at fault; within it, the first fix is.
      expectWithin('warm-up walk', runs, 0, slack: 21 + 2 * 8);
    });

    test('one false speed reading while still adds nothing', () {
      // Indoors, a phone lying still reported 1.86 m/s once.
      for (var seed = 0; seed < seeds; seed++) {
        final trace = TraceBuilder(seed: seed, accuracy: 10)..stay(minute * 10);
        final fixes = [
          for (final (i, fix) in trace.fixes.indexed)
            i == 300
                ? Fix(
                    time: fix.time,
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    accuracy: fix.accuracy,
                    speed: 1.86,
                  )
                : fix,
        ];

        expect(
          measure(TrackPolicy.expedition, fixes).meters,
          lessThan(30),
          reason: 'seed $seed',
        );
      }
    });
  });

  test('moving time leaves out a 10 min stop', () {
    final seconds = <double>[];
    addTearDown(() => report('moving-time (truth 600 s)', seconds, unit: ' s'));
    for (var seed = 0; seed < seeds; seed++) {
      final trace = TraceBuilder(seed: seed, accuracy: 5)
        ..move(duration: minute * 5, speed: 1)
        ..stay(minute * 10)
        ..move(duration: minute * 5, speed: 1);

      final moving = measure(TrackPolicy.expedition, trace.fixes).movingTime;
      seconds.add(moving.inMilliseconds / 1000);

      // Truly moving for 600 s. The anchor trails by up to one gate (20 s
      // at 1 m/s). The stretch spanning the stop is charged at the last
      // moving pace, so only position noise across the stop leaks in.
      expect(
        moving.inSeconds,
        inInclusiveRange(570, 640),
        reason: 'seed $seed',
      );
    }
  });

  test('replaying the stored track reproduces live stats exactly', () {
    const policy = TrackPolicy.expedition;
    final first = TraceBuilder(seed: 7, accuracy: 6)
      ..move(duration: minute * 20, speed: 1.2, heading: 40);
    final second = TraceBuilder(seed: 8, accuracy: 6)
      ..time = first.time.add(const Duration(hours: 1))
      ..east = 5000
      ..move(duration: minute * 20, speed: 1.2, heading: 220);

    final filter = FixFilter(policy);
    final live = TrackStats(policy);
    final stored = <List<Fix>>[];
    for (final segment in [first.fixes, second.fixes]) {
      filter.startSegment();
      live.startSegment();
      stored.add([]);
      for (final fix in segment) {
        if (filter.judge(fix).belongsInTrack) {
          stored.last.add(fix);
          live.add(fix);
        }
      }
    }

    final replayed = TrackStats.replay(policy, stored);

    expect(replayed.meters, live.meters);
    expect(replayed.movingTime, live.movingTime);
    // Two walks of about 1,440 m each; the 5 km between segments never
    // counts.
    final truth = first.trueMeters + second.trueMeters;
    expect(live.meters, closeTo(truth, truth * 0.03));
  });
}
