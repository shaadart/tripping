import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/record_screen.dart';
import 'package:tripping/app/system_access.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/location_source.dart';
import 'package:tripping/recording/recorder.dart';

import '../support/fakes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FlakyStore store;
  late FakeLocation location;
  late FakeSystemAccess system;
  late Recorder recorder;
  late DateTime now;

  setUp(() {
    store = FlakyStore(NativeDatabase.memory());
    location = FakeLocation();
    system = FakeSystemAccess();
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
          system: system,
          mapBuilder: (_, _) => const SizedBox.expand(),
          historyBuilder: (_) => const Scaffold(body: Text('History here')),
          clock: () => now,
        ),
      ),
    );
    await tester.pump(); // Android facts arrive.
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

  testWidgets('idle opens past journeys', (tester) async {
    await show(tester);

    await tester.tap(find.text('Past journeys'));
    await tester.pumpAndSettle();
    expect(find.text('History here'), findsOneWidget);
    await cleanUp(tester);
  });

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

  group('two kinds of journey (B1)', () {
    testWidgets('the road shows the GPS speed only while it is fresh', (
      tester,
    ) async {
      await show(tester);
      await tap(tester, 'Road journey');
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('Moving'), findsNothing);
      expect(find.text('—'), findsOneWidget);

      await act(
        tester,
        () async => location.emit(
          Fix(
            time: t0,
            latitude: 32,
            longitude: 77,
            accuracy: 5,
            speed: 13.9,
            heading: 90,
          ),
        ),
      );
      expect(find.text('50 km/h'), findsOneWidget);

      now = t0.add(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('—'), findsOneWidget);
      await cleanUp(tester);
    });

    testWidgets('an expedition shows coordinates on demand, and copies them', (
      tester,
    ) async {
      await show(tester);
      await tap(tester, 'Expedition');
      expect(find.text('Moving'), findsOneWidget);
      expect(find.text('Speed'), findsNothing);
      expect(find.text('Show coordinates'), findsNothing);

      await act(tester, () async => location.emit(walkFix(0)));
      expect(find.textContaining('° N'), findsNothing);
      await tester.tap(find.text('Show coordinates'));
      await tester.pump();
      expect(find.text('32.00000° N, 77.00000° E ±3 m'), findsOneWidget);

      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call.arguments);
          return null;
        },
      );
      await tester.tap(find.byTooltip('Copy coordinates'));
      await tester.pump();
      expect(copied, [
        {'text': '32.00000, 77.00000'},
      ]);
      expect(find.text('Coordinates copied'), findsOneWidget);

      now = t0.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Last known:'), findsOneWidget);
      await cleanUp(tester);
    });
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
  group('background recording (R5)', () {
    Future<void> interruptedJourney(WidgetTester tester) async {
      await tester.runAsync(() async {
        final before = await Recorder.open(store, location, clock: () => now);
        await before.start(JourneyMode.expedition);
        location.emit(walkFix(0));
        location.emit(walkFix(30));
        await before.close();
      });
    }

    testWidgets('asks to show the notification before recording starts', (
      tester,
    ) async {
      system
        ..notificationsShown = false
        ..grantOnRequest = false;
      await show(tester);

      await tap(tester, 'Expedition');

      expect(system.notificationRequests, 1);
      expect(find.text('Recording · Expedition'), findsOneWidget);
      expect(
        find.textContaining('Android isn’t showing its notification'),
        findsOneWidget,
      );
      await cleanUp(tester);
    });

    testWidgets('does not ask again once notifications are shown', (
      tester,
    ) async {
      await show(tester);

      await tap(tester, 'Road journey');

      expect(system.notificationRequests, 0);
      expect(
        find.textContaining('Android isn’t showing its notification'),
        findsNothing,
      );
      await cleanUp(tester);
    });

    testWidgets('a Restricted battery setting is flagged before starting', (
      tester,
    ) async {
      system.restricted = true;
      await show(tester);

      expect(find.textContaining('set to Restricted'), findsOneWidget);
      await tap(tester, 'Open settings');
      expect(system.appSettingsOpened, 1);
      await cleanUp(tester);
    });

    testWidgets('no fix 30 s after starting is flagged', (tester) async {
      await show(tester);
      await tap(tester, 'Expedition');
      expect(find.text('Waiting for GPS…'), findsOneWidget);

      now = t0.add(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('No GPS fix yet after 45 s'), findsOneWidget);
      await cleanUp(tester);
    });

    testWidgets('an interruption the user caused is not blamed on battery', (
      tester,
    ) async {
      system.exits = [
        LastExit(ExitCause.user, t0.add(const Duration(minutes: 1))),
      ];
      await interruptedJourney(tester);

      await show(tester);

      expect(find.textContaining('stopped from Active apps'), findsOneWidget);
      expect(find.text('Battery settings'), findsNothing);
      await cleanUp(tester);
    });

    testWidgets('a swipe from recent apps is named as such', (tester) async {
      system.exits = [
        LastExit(ExitCause.swiped, t0.add(const Duration(minutes: 1))),
      ];
      await interruptedJourney(tester);

      await show(tester);

      expect(find.textContaining('swiped away from recent apps'), findsOne);
      expect(find.text('Battery settings'), findsNothing);
      await cleanUp(tester);
    });

    testWidgets('an interruption by the phone offers battery settings', (
      tester,
    ) async {
      system.exits = [
        LastExit(ExitCause.system, t0.add(const Duration(minutes: 1))),
      ];
      await interruptedJourney(tester);
      await show(tester);

      expect(find.textContaining('The phone closed Tripping'), findsOneWidget);
      await tap(tester, 'Battery settings');
      expect(system.appSettingsOpened, 1);
      await cleanUp(tester);
    });

    testWidgets('the first exit after the last fix is the cause', (
      tester,
    ) async {
      // Newest first, as Android returns them: a later update must not be
      // blamed for an earlier interruption (seen on the Pixel, E-013).
      system.exits = [
        LastExit(ExitCause.update, t0.add(const Duration(hours: 2))),
        LastExit(ExitCause.system, t0.add(const Duration(minutes: 1))),
      ];
      await interruptedJourney(tester);

      await show(tester);

      expect(find.textContaining('updated'), findsNothing);
      expect(find.textContaining('The phone closed Tripping'), findsOneWidget);
      await cleanUp(tester);
    });

    testWidgets('an exit from long before the interruption is ignored', (
      tester,
    ) async {
      system.exits = [
        LastExit(ExitCause.crash, t0.subtract(const Duration(hours: 3))),
      ];
      await interruptedJourney(tester);

      await show(tester);

      expect(find.textContaining('crashed'), findsNothing);
      expect(find.textContaining('The phone closed Tripping'), findsOneWidget);
      await cleanUp(tester);
    });
  });
}

extension on FlakyStore {
  Future<int> allJournalsCount(WidgetTester tester) async =>
      (await tester.runAsync(allJourneys))!.length;
}
