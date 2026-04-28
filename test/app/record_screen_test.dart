import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/record_screen.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/location_source.dart';
import 'package:tripping/recording/recorder.dart';

import '../support/fakes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FlakyStore store;
  late FakeLocation location;
  late Recorder recorder;
  late DateTime now;

  setUp(() {
    store = FlakyStore(NativeDatabase.memory());
    location = FakeLocation();
    now = t0;
  });

  /// Runs [work] with real async (the database and recorder need it), lets
  /// the recorder finish, then redraws.
  Future<void> act(WidgetTester tester, Future<void> Function() work) async {
    await tester.runAsync(() async {
      await work();
      await recorder.settled();
    });
    await tester.pump();
  }

  Future<void> show(WidgetTester tester) async {
    await tester.runAsync(() async {
      recorder = await Recorder.open(store, location, clock: () => now);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingTheme(Brightness.light),
        home: RecordScreen(
          recorder: recorder,
          location: location,
          clock: () => now,
        ),
      ),
    );
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await recorder.close();
      await store.close();
    });
  }

  Future<void> tap(WidgetTester tester, String label) =>
      act(tester, () async => tester.tap(find.text(label)));

  testWidgets('idle offers both kinds of journey', (tester) async {
    await show(tester);

    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Road journey'), findsOneWidget);
    expect(find.text('Expedition'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('a refused permission is explained and can be asked again', (
    tester,
  ) async {
    location.access = LocationAccess.denied;
    await show(tester);

    await tap(tester, 'Expedition');

    expect(find.textContaining('needs your location'), findsOneWidget);
    location.access = LocationAccess.granted;
    await tap(tester, 'Allow location');
    expect(location.requests, 2);
    expect(find.text('Recording · Expedition'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('permission refused for good points to Settings', (tester) async {
    location.access = LocationAccess.deniedForever;
    await show(tester);

    await tap(tester, 'Road journey');
    await tap(tester, 'Open settings');

    expect(find.textContaining('not allowed for Tripping'), findsOneWidget);
    expect(location.settingsOpened, [LocationAccess.deniedForever]);
    expect(location.requests, 1);
    await cleanUp(tester);
  });

  testWidgets('approximate-only location asks for precise location', (
    tester,
  ) async {
    location.access = LocationAccess.approximate;
    await show(tester);

    await tap(tester, 'Expedition');

    expect(find.textContaining('only has approximate location'), findsOne);
    expect(await store.allJournalsCount(tester), 0);
    await cleanUp(tester);
  });

  testWidgets('recording shows GPS honestly as it arrives and goes quiet', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Expedition');
    expect(find.text('Recording · Expedition'), findsOneWidget);
    expect(find.text('Waiting for GPS…'), findsOneWidget);

    await act(tester, () async => location.emit(walkFix(0)));
    expect(find.text('GPS ±3 m'), findsOneWidget);

    now = t0.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No GPS fix for 20 s'), findsOneWidget);
    expect(find.text('0:00:20'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('a failing save is shown, not hidden', (tester) async {
    await show(tester);
    await tap(tester, 'Expedition');
    store.failAppends = true;

    await act(tester, () async => location.emit(walkFix(0)));

    expect(find.textContaining('Can’t save to this phone'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('pause, resume and end, with a confirmation before ending', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Road journey');

    await tap(tester, 'Pause');
    expect(find.text('Paused · Road journey'), findsOneWidget);
    await tap(tester, 'Resume');
    expect(find.text('Recording · Road journey'), findsOneWidget);

    await tap(tester, 'End journey');
    expect(find.text('End this journey?'), findsOneWidget);
    await tap(tester, 'Keep going');
    expect(find.text('Recording · Road journey'), findsOneWidget);

    await tap(tester, 'End journey');
    await act(
      tester,
      () async => tester.tap(find.widgetWithText(TextButton, 'End journey')),
    );
    await tester.pump();
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.textContaining('Journey saved'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('a journey cut off by a process death says so on reopening', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final before = await Recorder.open(store, location, clock: () => now);
      await before.start(JourneyMode.expedition);
      location.emit(walkFix(0));
      location.emit(walkFix(30));
      await before.close();
    });

    await show(tester);

    expect(find.text('Stopped · Expedition'), findsOneWidget);
    expect(find.textContaining('Recording stopped at'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await cleanUp(tester);
  });
}

extension on FlakyStore {
  Future<int> allJournalsCount(WidgetTester tester) async =>
      (await tester.runAsync(allJourneys))!.length;
}
