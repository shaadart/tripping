import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/history/gpx.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

import '../support/fakes.dart';

void main() {
  String gpx(List<List<Fix>> track, {String name = 'Walk'}) => gpxOf(
    name: name,
    mode: JourneyMode.expedition,
    startedAt: t0,
    track: track,
  );

  test('one trkseg per recorded segment, never joined', () {
    final out = gpx([
      [walkFix(0), walkFix(1)],
      const [],
      [walkFix(100)],
    ]);
    expect('<trkseg>'.allMatches(out), hasLength(2));
    expect('<trkpt '.allMatches(out), hasLength(3));
    expect(out, contains('<type>expedition</type>'));
  });

  test('writes position and UTC time to the precision recorded', () {
    final out = gpx([
      [walkFix(0)],
    ]);
    final fix = walkFix(0);
    expect(
      out,
      contains(
        '<trkpt lat="${fix.latitude.toStringAsFixed(7)}" lon="77.0000000">'
        '<time>2026-10-28T06:00:00.000Z</time></trkpt>',
      ),
    );
    expect(out, contains('<metadata>'));
    expect(out, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
  });

  test('altitude only when the phone measured it', () {
    final high = Fix(time: t0, latitude: 32, longitude: 77, altitude: 2050.04);
    expect(
      gpx([
        [high],
      ]),
      contains('<ele>2050.0</ele>'),
    );
    expect(
      gpx([
        [walkFix(0)],
      ]),
      isNot(contains('<ele>')),
    );
  });

  test('a name cannot break the XML', () {
    final out = gpx(const [], name: 'Tom & Jerry <"trip">');
    expect(
      out,
      contains('<name>Tom &amp; Jerry &lt;&quot;trip&quot;&gt;</name>'),
    );
  });

  group('waypoints', () {
    final marked = WaypointRow(
      id: 1,
      journeyId: 1,
      kind: WaypointKind.marked,
      createdAt: t0.add(const Duration(seconds: 3)),
      latitude: 32.1234567,
      longitude: 77.7654321,
      accuracy: 6,
      altitude: 2100.04,
      fixTime: t0.add(const Duration(seconds: 2)),
      name: 'Spring & camp',
      note: 'Water <cold>',
    );
    final planned = WaypointRow(
      id: 2,
      journeyId: 1,
      kind: WaypointKind.planned,
      createdAt: t0.add(const Duration(minutes: 1)),
      latitude: 32.2,
      longitude: 77.8,
    );

    String withWaypoints() => gpxOf(
      name: 'Walk',
      mode: JourneyMode.expedition,
      startedAt: t0,
      track: [
        [walkFix(0)],
      ],
      waypoints: [marked, planned],
    );

    test('come before the track, as GPX requires', () {
      final out = withWaypoints();
      expect(out.indexOf('<wpt '), lessThan(out.indexOf('<trk>')));
      expect('<wpt '.allMatches(out), hasLength(2));
    });

    test('a marked one keeps its fix time, altitude, name and note', () {
      expect(
        withWaypoints(),
        contains(
          '<wpt lat="32.1234567" lon="77.7654321"><ele>2100.0</ele>'
          '<time>2026-10-28T06:00:02.000Z</time>'
          '<name>Spring &amp; camp</name><desc>Water &lt;cold&gt;</desc>'
          '<type>marked</type></wpt>',
        ),
      );
    });

    test('a planned one has only what is known', () {
      expect(
        withWaypoints(),
        contains(
          '<wpt lat="32.2000000" lon="77.8000000">'
          '<time>2026-10-28T06:01:00.000Z</time><type>planned</type></wpt>',
        ),
      );
    });
  });
}
