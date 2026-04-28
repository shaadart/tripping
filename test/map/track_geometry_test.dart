import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/map/track_geometry.dart';

import '../support/fakes.dart';

List<Object?> coordinatesOf(Map<String, Object> collection) => [
  for (final feature in collection['features']! as List<Object?>)
    ((feature! as Map)['geometry'] as Map)['coordinates'],
];

void main() {
  group('trackFeatures', () {
    test('one line per segment, never joined, longitude first', () {
      final features = trackFeatures([
        [walkFix(0), walkFix(1)],
        [walkFix(10)], // a single fix is not a line
        [walkFix(20), walkFix(21), walkFix(22)],
      ]);

      final lines = coordinatesOf(features);
      expect(lines, hasLength(2));
      expect((lines.first! as List).first, [
        walkFix(0).longitude,
        walkFix(0).latitude,
      ]);
      expect((lines.last! as List), hasLength(3));
    });
  });

  group('accuracy circle', () {
    test('keeps its true ground size at every zoom', () {
      const meters = 25.0;
      for (final latitude in [0.0, 32.2, 60.0]) {
        final radiusZ0 = radiusAtZoom0(meters, latitude);
        for (final zoom in [0, 10, 16, 22]) {
          final metersPerPixel =
              2 * pi * 6378137 / 512 * cos(latitude * pi / 180) / pow(2, zoom);
          expect(
            radiusZ0 * pow(2, zoom),
            closeTo(meters / metersPerPixel, 1e-9),
          );
        }
      }
    });

    test('is twice as wide in pixels at 60° as at the equator', () {
      expect(radiusAtZoom0(10, 60) / radiusAtZoom0(10, 0), closeTo(2, 1e-9));
    });
  });

  group('positionFeatures', () {
    Map<Object?, Object?> propertiesOf(Map<String, Object> collection) =>
        ((collection['features']! as List).single as Map)['properties'] as Map;

    test('nothing to draw without a fix', () {
      final features = positionFeatures(null, stale: false, maxAccuracy: 50);
      expect(features['features'], isEmpty);
    });

    test('a fresh, precise fix is solid', () {
      final properties = propertiesOf(
        positionFeatures(walkFix(0), stale: false, maxAccuracy: 50),
      );
      expect(properties['hollow'], isFalse);
      expect(properties['stale'], isFalse);
    });

    test('a stale or imprecise fix is hollow', () {
      final vague = Fix(time: t0, latitude: 32, longitude: 77, accuracy: 400);
      expect(
        propertiesOf(
          positionFeatures(vague, stale: false, maxAccuracy: 50),
        )['hollow'],
        isTrue,
      );
      expect(
        propertiesOf(
          positionFeatures(walkFix(0), stale: true, maxAccuracy: 50),
        )['hollow'],
        isTrue,
      );
    });
  });

  group('TrackBuffer', () {
    test('history and tail together draw every fix, joined by one', () {
      final buffer = TrackBuffer();
      for (var second = 0; second < 150; second++) {
        buffer.add(walkFix(second));
        if (buffer.tailIsLong) buffer.foldTail();
      }

      final history = buffer.history.toList();
      final tail = buffer.tail;
      expect(history.single.last, tail.first);
      expect(history.single.length + tail.length - 1, 150);
      expect(tail.length, lessThanOrEqualTo(TrackBuffer.tailLimit + 1));
    });

    test('a new segment starts a separate tail', () {
      final buffer = TrackBuffer()
        ..reset([
          [walkFix(0), walkFix(1)],
        ])
        ..startSegment()
        ..add(walkFix(100));

      expect(buffer.history.map((s) => s.length), [2, 0]);
      expect(buffer.tail, [walkFix(100)]);
      expect(buffer.lastFix, walkFix(100));
    });

    test('reset copies the stored track', () {
      final stored = [
        [walkFix(0)],
      ];
      final buffer = TrackBuffer()..reset(stored);
      buffer.add(walkFix(1));

      expect(stored.single, hasLength(1));
    });
  });
}
