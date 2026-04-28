import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/map/track_geometry.dart';

import '../support/fakes.dart';
import '../support/geometry.dart';
import '../support/traces.dart';

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

  group('boundsOf', () {
    test('spans every fix of every segment', () {
      final box = boundsOf([
        [walkFix(0), walkFix(10)],
        const [],
        [walkFix(100)],
      ])!;
      expect(box.south, walkFix(0).latitude);
      expect(box.north, walkFix(100).latitude);
      expect(box.west, 77);
      expect(box.east, 77);
    });

    test('is null without fixes', () {
      expect(boundsOf(const [[]]), isNull);
    });
  });

  group('endsFeatures', () {
    test('marks the first and last fix of the journey', () {
      final ends = endsFeatures([
        [walkFix(0), walkFix(1)],
        [walkFix(100), walkFix(101)],
      ]);
      expect(coordinatesOf(ends), [
        [walkFix(0).longitude, walkFix(0).latitude],
        [walkFix(101).longitude, walkFix(101).latitude],
      ]);
    });

    test('a single fix is only a start', () {
      expect(
        coordinatesOf(
          endsFeatures([
            [walkFix(0)],
          ]),
        ),
        hasLength(1),
      );
    });
  });

  test('waypoints carry their kind and a label: name, else number', () {
    WaypointRow waypoint(int id, WaypointKind kind, {String? name}) =>
        WaypointRow(
          id: id,
          journeyId: 1,
          kind: kind,
          createdAt: t0,
          latitude: 32,
          longitude: 77 + id / 1000,
          name: name,
        );
    final features =
        waypointFeatures([
              waypoint(1, WaypointKind.marked, name: 'Spring'),
              waypoint(2, WaypointKind.planned),
            ])['features']!
            as List;
    final properties = [
      for (final feature in features) (feature as Map)['properties'],
    ];
    expect(properties, [
      {'kind': 'marked', 'label': 'Spring'},
      {'kind': 'planned', 'label': '2'},
    ]);
    expect(coordinatesOf({'features': features}).last, [77.002, 32]);
  });

  test('a route is one line marked road or straight, longitude first', () {
    final road = routeFeatures(const [
      (12.97, 77.59),
      (12.95, 77.58),
    ], RouteKind.road);
    expect(coordinatesOf(road).single, [
      [77.59, 12.97],
      [77.58, 12.95],
    ]);
    final straight = routeFeatures(const [
      (12.97, 77.59),
      (12.95, 77.58),
    ], RouteKind.straight);
    expect(
      (((straight['features']! as List).single as Map)['properties']
          as Map)['kind'],
      'straight',
    );
    expect(
      routeFeatures(const [(12.97, 77.59)], RouteKind.road)['features'],
      isEmpty,
    );
  });

  test('a destination is a named point', () {
    final feature =
        (destinationFeatures('Lalbagh', 12.95, 77.58)['features']! as List)
                .single
            as Map;
    expect(feature['properties'], {'name': 'Lalbagh'});
    expect((feature['geometry'] as Map)['coordinates'], [77.58, 12.95]);
  });

  group('TrackBuffer', () {
    /// Adds [fixes] the way the live map does.
    void record(
      TrackBuffer buffer,
      Iterable<Fix> fixes, {
      void Function()? onFold,
    }) {
      for (final fix in fixes) {
        buffer.add(fix);
        if (buffer.tailIsLong) {
          buffer.foldTail();
          onFold?.call();
        }
      }
    }

    test('history and tail draw every fix within the tolerance, joined', () {
      final trace = TraceBuilder(seed: 2, accuracy: 5)
        ..move(duration: const Duration(minutes: 4), speed: 1.4, heading: 10)
        ..move(duration: const Duration(minutes: 4), speed: 1.4, heading: 200);
      final buffer = TrackBuffer();
      record(buffer, trace.fixes);

      final history = buffer.history.single;
      final tail = buffer.tail;
      expect(history.last, tail.first);
      expect(history.first, trace.fixes.first);
      expect(tail.last, trace.fixes.last);
      final drawn = [...history, ...tail.skip(1)];
      expect(drawn.length, lessThan(trace.fixes.length));
      for (final fix in trace.fixes) {
        expect(distanceToLine(fix, drawn), lessThan(buffer.tolerance + 0.1));
      }
    });

    test('a straight line folds down to its ends', () {
      final buffer = TrackBuffer();
      record(buffer, [for (var s = 0; s < 500; s++) walkFix(s)]);
      expect(buffer.history.single, hasLength(lessThan(10)));
    });

    test('folds less often once the history is long', () {
      // A zigzag of 10 m teeth: simplification cannot drop any of it.
      Fix zig(int i) => Fix(
        time: t0.add(Duration(seconds: i)),
        latitude: 32 + (i.isEven ? 0 : 10) / metersPerDegree,
        longitude: 77 + i * 10 / (metersPerDegree * 0.848),
      );
      final buffer = TrackBuffer()
        ..reset([
          [for (var i = 0; i < 10000; i++) zig(i)],
        ]);
      expect(buffer.history.single, hasLength(10000));

      var added = 0;
      while (!buffer.tailIsLong) {
        buffer.add(zig(10000 + added++));
      }
      // √10000 = 100 fixes rather than the 60 of a short journey.
      expect(added, 100 + 1);
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
