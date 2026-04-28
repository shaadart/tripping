import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/geo.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/simplify.dart';

import '../support/fakes.dart';
import '../support/geometry.dart';
import '../support/traces.dart';

void main() {
  test('a straight walk keeps only its ends', () {
    final line = [for (var s = 0; s < 600; s++) walkFix(s)];
    expect(simplify(line, 1), [line.first, line.last]);
  });

  test('short lines are returned as they are', () {
    expect(simplify(const [], 1), isEmpty);
    expect(simplify([walkFix(0), walkFix(1)], 1), hasLength(2));
  });

  test('every dropped fix stays within the tolerance', () {
    final trace = TraceBuilder(seed: 7, accuracy: 5)
      ..move(duration: const Duration(minutes: 5), speed: 1.4, heading: 30)
      ..move(duration: const Duration(minutes: 3), speed: 1.4, heading: 120)
      ..move(duration: const Duration(minutes: 4), speed: 1.4, heading: 270);
    final line = trace.fixes;

    for (final tolerance in [2.0, 10.0]) {
      final simple = simplify(line, tolerance);
      expect(simple.first, line.first);
      expect(simple.last, line.last);
      expect(simple.length, lessThan(line.length ~/ 3));
      for (final fix in line) {
        // The sampled distance overestimates by at most a few centimetres.
        expect(distanceToLine(fix, simple), lessThan(tolerance + 0.1));
      }
    }
  });

  test('keeps the corner of a turn', () {
    final out = [for (var s = 0; s <= 100; s++) walkFix(s)];
    final corner = out.last;
    final back = [
      for (var s = 1; s <= 100; s++)
        Fix(
          time: corner.time.add(Duration(seconds: s)),
          latitude: corner.latitude,
          longitude: corner.longitude + 1.5 * s / (metersPerDegree * 0.848),
        ),
    ];
    final simple = simplify([...out, ...back], 1);
    expect(simple, [out.first, corner, back.last]);
    expect(simple[0].metersTo(simple[1]), closeTo(150, 0.5));
  });

  test('a day at one fix per second simplifies quickly', () {
    final trace = TraceBuilder(seed: 3, accuracy: 5);
    for (var hour = 0; hour < 12; hour++) {
      trace.move(
        duration: const Duration(hours: 1),
        speed: 15,
        heading: hour * 37.0 % 360,
      );
    }
    final watch = Stopwatch()..start();
    final simple = simplify(trace.fixes, 2);
    watch.stop();
    expect(trace.fixes, hasLength(43200));
    expect(simple.length, lessThan(trace.fixes.length));
    // Generous for a slow CI host; the device measurement is what counts.
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });
}
