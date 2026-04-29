import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/history_screen.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/history/elevation_profile.dart';
import 'package:tripping/history/journey_history.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/places/polyline.dart';

import '../support/fakes.dart';

/// Past journeys held in memory.
class FakeHistory implements JourneyHistory {
  FakeHistory(this.journeys);

  final List<PastJourney> journeys;
  final deleted = <int>[];

  /// Where every journey was going; none by default.
  RouteRow? route;

  @override
  Future<RouteRow?> routeOf(int journeyId) async => route;

  @override
  Future<List<PastJourney>> load() async => [...journeys];

  @override
  Future<List<List<Fix>>> trackOf(
    int journeyId, {
    double tolerance = 1,
  }) async => [
    [walkFix(0), walkFix(60)],
    [walkFix(120), walkFix(180)],
  ];

  @override
  Future<List<WaypointRow>> waypointsOf(int journeyId) async => [
    WaypointRow(
      id: 1,
      journeyId: journeyId,
      kind: WaypointKind.marked,
      createdAt: t0.add(const Duration(minutes: 1)),
      latitude: 32.001,
      longitude: 77,
      accuracy: 6,
      fixTime: t0.add(const Duration(minutes: 1)),
      name: 'Spring',
      note: 'Cold water',
    ),
    WaypointRow(
      id: 2,
      journeyId: journeyId,
      kind: WaypointKind.planned,
      createdAt: t0.add(const Duration(minutes: 2)),
      latitude: 32.01,
      longitude: 77.01,
    ),
  ];

  /// A profile only for journey 1, so both cases are seen.
  @override
  Future<ElevationProfile?> elevationOf(PastJourney past) async =>
      past.journey.id == 1
      ? const ElevationProfile(
          climb: 123,
          descent: 45,
          lowest: 2000,
          highest: 2100,
          meters: 1234,
          lines: [
            [(0, 2000), (600, 2100), (1234, 2060)],
          ],
        )
      : null;

  @override
  Future<String> gpxOf(PastJourney past, {required String name}) async =>
      '<gpx/>';

  @override
  Future<void> delete(int journeyId) async {
    deleted.add(journeyId);
    journeys.removeWhere((p) => p.journey.id == journeyId);
  }
}

PastJourney pastWalk(int id) => PastJourney(
  journey: JourneyRow(
    id: id,
    uuid: 'u-$id',
    mode: JourneyMode.expedition,
    status: JourneyStatus.ended,
    createdAt: t0,
    endedAt: t0.add(const Duration(minutes: 4)),
  ),
  meters: 1234,
  movingTime: const Duration(minutes: 3),
  recordedTime: const Duration(minutes: 4),
  outline: [
    [(latitude: 32, longitude: 77), (latitude: 32.001, longitude: 77)],
    [(latitude: 32.002, longitude: 77), (latitude: 32.003, longitude: 77.001)],
  ],
);

void main() {
  late List<List<List<Fix>>> drawn;
  var shownWaypoints = <WaypointRow>[];
  RouteRow? shownRoute;

  setUp(() => drawn = []);

  Future<void> show(
    WidgetTester tester,
    FakeHistory history, {
    Future<void> Function(PastJourney past)? onExport,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingTheme(Brightness.light),
        home: HistoryScreen(
          history: history,
          trackMapBuilder: (track, waypoints, route) {
            if (track != null) drawn.add(track);
            shownWaypoints = waypoints;
            shownRoute = route;
            return const SizedBox.expand();
          },
          onExport: onExport,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('says so when there are no journeys', (tester) async {
    await show(tester, FakeHistory([]));
    expect(find.textContaining('No journeys yet'), findsOneWidget);
  });

  testWidgets('lists journeys with their numbers', (tester) async {
    await show(tester, FakeHistory([pastWalk(1), pastWalk(2)]));
    expect(find.text('Expedition · 1.23 km · 0:04:00'), findsNWidgets(2));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('a journey opens on its map, with parts never joined', (
    tester,
  ) async {
    await show(tester, FakeHistory([pastWalk(1)]));
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00'));
    await tester.pumpAndSettle();

    expect(drawn.single, hasLength(2));
    expect(find.text('1.23 km'), findsOneWidget);
    expect(find.text('0:03:00'), findsOneWidget);
    expect(find.textContaining('Recorded in 2 parts'), findsOneWidget);
  });

  testWidgets('waypoints are on the map and listed, numbered alike', (
    tester,
  ) async {
    await show(tester, FakeHistory([pastWalk(1)]));
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00'));
    await tester.pumpAndSettle();

    expect(shownWaypoints, hasLength(2));
    expect(find.text('Waypoints'), findsOneWidget);
    expect(find.text('Spring'), findsOneWidget);
    expect(find.text('Cold water'), findsOneWidget);
    expect(find.textContaining('Marked'), findsOneWidget);
    expect(find.textContaining('±6 m'), findsOneWidget);
    expect(find.text('Waypoint 2'), findsOneWidget);
    expect(find.textContaining('Planned'), findsOneWidget);
  });

  RouteRow routeTo(double north, {RouteKind kind = RouteKind.road}) => RouteRow(
    journeyId: 1,
    destination: 'Camp',
    latitude: 32 + north / metersPerDegree,
    longitude: 77,
    kind: kind,
    provider: 'valhalla',
    computedAt: t0,
    meters: 6300,
    seconds: 1300,
    geometry: encodePolyline([(32, 77), (32 + north / metersPerDegree, 77)]),
  );

  testWidgets('the destination, the way planned, and whether it was reached', (
    tester,
  ) async {
    // The walk ends 270 m north of its start.
    final history = FakeHistory([pastWalk(1)])..route = routeTo(280);
    await show(tester, history);
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00'));
    await tester.pumpAndSettle();
    expect(shownRoute?.destination, 'Camp');
    expect(find.text('To Camp'), findsOneWidget);
    expect(find.text('Planned 6.30 km on foot · Reached'), findsOneWidget);
  });

  testWidgets('a straight line that was never reached says both', (
    tester,
  ) async {
    final history = FakeHistory([pastWalk(1)])
      ..route = routeTo(2000, kind: RouteKind.straight);
    await show(tester, history);
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00'));
    await tester.pumpAndSettle();
    expect(
      find.text('6.30 km in a straight line, not along a path · Not reached'),
      findsOneWidget,
    );
  });

  testWidgets('without a destination there is no destination line', (
    tester,
  ) async {
    await show(tester, FakeHistory([pastWalk(1)]));
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00'));
    await tester.pumpAndSettle();
    expect(find.textContaining('To '), findsNothing);
    expect(shownRoute, isNull);
  });

  testWidgets('climb, descent and the height chart, only when known', (
    tester,
  ) async {
    await show(tester, FakeHistory([pastWalk(1), pastWalk(2)]));
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00').first);
    await tester.pumpAndSettle();
    expect(find.text('Climb 123 m · Descent 45 m'), findsOneWidget);
    expect(find.text('2100 m'), findsOneWidget);
    expect(find.text('2000 m'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Climb'), findsNothing);
  });

  testWidgets('deleting asks first, then removes the journey', (tester) async {
    final history = FakeHistory([pastWalk(1)]);
    await show(tester, history);
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete journey'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(history.deleted, isEmpty);

    await tester.tap(find.byTooltip('Delete journey'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(history.deleted, [1]);
    expect(find.textContaining('No journeys yet'), findsOneWidget);
  });

  testWidgets('exports the journey, and says so when it cannot', (
    tester,
  ) async {
    final exported = <int>[];
    var fail = false;
    await show(
      tester,
      FakeHistory([pastWalk(7)]),
      onExport: (past) async {
        if (fail) throw const FileSystemException('disk full');
        exported.add(past.journey.id);
      },
    );
    await tester.tap(find.text('Expedition · 1.23 km · 0:04:00'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export GPX'));
    await tester.pumpAndSettle();
    expect(exported, [7]);

    fail = true;
    await tester.tap(find.byTooltip('Export GPX'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't export"), findsOneWidget);
  });
}
