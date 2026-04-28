import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/history_screen.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/history/journey_history.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

import '../support/fakes.dart';

/// Past journeys held in memory.
class FakeHistory implements JourneyHistory {
  FakeHistory(this.journeys);

  final List<PastJourney> journeys;
  final deleted = <int>[];

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
          trackMapBuilder: (track) {
            if (track != null) drawn.add(track);
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
