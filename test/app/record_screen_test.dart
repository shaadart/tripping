import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/record_screen.dart';
import 'package:tripping/app/system_access.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/map/offline_maps.dart';
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
  final savedOffline = ValueNotifier<List<OfflineMap>>(const []);
  var sunToggles = 0;

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
    final closed = find.descendant(
      of: find.byTooltip('Journey details'),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.expanded == false,
      ),
    );
    if (closed.evaluate().isNotEmpty &&
        find.byTooltip('Journey details').hitTestable().evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Journey details'));
      await tester.pump();
    }
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
          mapBuilder: (_, _) => const SizedBox.expand(key: Key('journey-map')),
          waypoints: store,
          historyBuilder: (_) => const Scaffold(body: Text('History here')),
          savedOffline: savedOffline,
          offlineMapsBuilder: (_) =>
              Scaffold(appBar: AppBar(), body: const Text('Offline maps here')),
          onToggleHighSun: () => sunToggles++,
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

  testWidgets(
    'compact journey panel gives the map room and expands without changing recording',
    (tester) async {
      await show(tester);
      await tester.runAsync(() async {
        await recorder.start(JourneyMode.expedition);
        await recorder.settled();
      });
      await tester.pump();
      await tester.runAsync(() async {
        location.emit(walkFix(0));
        await recorder.settled();
      });
      await tester.pump();
      final map = find.byKey(const Key('journey-map'));
      final compactHeight = tester.getSize(map).height;
      expect(
        compactHeight,
        greaterThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio * .5,
        ),
      );
      expect(find.text('Show coordinates'), findsNothing);
      expect(find.text('Pause'), findsOneWidget);
      final before = (recorder.state as Recording).journey.uuid;
      final requests = location.requests;
      await tester.tap(find.byTooltip('Journey details'));
      await tester.pump();
      expect(tester.getSize(map).height, lessThan(compactHeight));
      expect(find.text('Show coordinates'), findsOneWidget);
      expect((recorder.state as Recording).journey.uuid, before);
      expect(location.requests, requests);
      await cleanUp(tester);
    },
  );

  testWidgets('the sun button asks for the high-sun look', (tester) async {
    sunToggles = 0;
    await show(tester);
    await tester.tap(find.byTooltip('High-sun mode'));
    expect(sunToggles, 1);
    await cleanUp(tester);
  });

  testWidgets('pause and end sit side by side', (tester) async {
    await show(tester);
    await tap(tester, 'Expedition');
    expect(
      tester.getCenter(find.text('Pause')).dy,
      closeTo(tester.getCenter(find.text('End journey')).dy, 1),
    );
    await cleanUp(tester);
  });

  testWidgets('with large text, pause and end stack instead', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(tester);
    // The panel scrolls rather than overflow at this size.
    await tester.ensureVisible(find.text('Expedition'));
    await tester.pumpAndSettle();
    await tap(tester, 'Expedition');
    expect(
      tester.getCenter(find.text('Pause')).dy,
      lessThan(tester.getCenter(find.text('End journey')).dy),
    );
    await cleanUp(tester);
  });

  testWidgets('a trip inside a saved area says the map works offline', (
    tester,
  ) async {
    OfflineMap around(
      (double, double, double, double) box, {
      bool done = true,
    }) => OfflineMap(
      id: 1,
      name: 'Here',
      area: (south: box.$1, west: box.$2, north: box.$3, east: box.$4),
      release: 'r1',
      savedAt: t0,
      bytes: 1,
      complete: done,
      progress: done ? 1 : 0.5,
    );
    savedOffline.value = [around((31.9, 76.9, 32.1, 77.1))];
    await show(tester);
    expect(find.text('Offline map saved for this area'), findsNothing);

    await tap(tester, 'Expedition');
    await act(tester, () async => location.emit(walkFix(0)));
    expect(find.text('Offline map saved for this area'), findsOneWidget);

    savedOffline.value = [around((31.9, 76.9, 32.1, 77.1), done: false)];
    await tester.pump();
    expect(find.text('Offline map saved for this area'), findsNothing);

    savedOffline.value = [around((40, 76.9, 41, 77.1))];
    await tester.pump();
    expect(find.text('Offline map saved for this area'), findsNothing);
    savedOffline.value = const [];
    await cleanUp(tester);
  });

  testWidgets('offline maps open from home, and during a trip', (tester) async {
    await show(tester);
    expect(find.byTooltip('Offline maps'), findsNothing);
    await tester.tap(find.text('Offline maps'));
    await tester.pumpAndSettle();
    expect(find.text('Offline maps here'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tap(tester, 'Expedition');
    await tester.tap(find.byTooltip('Map options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline maps'));
    await tester.pumpAndSettle();
    expect(find.text('Offline maps here'), findsOneWidget);
    await cleanUp(tester);
  });

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
    expect(find.text('Recording'), findsOneWidget);
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
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('Waiting for GPS…'), findsOneWidget);

    await act(tester, () async => location.emit(walkFix(0)));
    expect(find.text('GPS ±3 m'), findsOneWidget);

    now = t0.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No GPS fix for 20 s'), findsOneWidget);
    expect(find.text('0:00:20'), findsOneWidget);
    await cleanUp(tester);
  });

  group('waypoints (X1)', () {
    Future<List<WaypointRow>> stored(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final journey = await store.activeJourney();
          return store.waypointsOf(journey!.id);
        }))!;

    Finder markButton() => find.ancestor(
      of: find.text('Mark'),
      matching: find.byWidgetPredicate((w) => w is TextButton),
    );

    testWidgets('mark saves the fix at once, then names it', (tester) async {
      await show(tester);
      await tap(tester, 'Expedition');
      expect(
        tester.widget<TextButton>(markButton()).onPressed,
        isNull,
        reason: 'nothing to mark before the first fix',
      );

      await act(tester, () async => location.emit(walkFix(0)));
      await act(tester, () async => tester.tap(markButton()));
      await tester.pumpAndSettle();
      expect(find.text('Marked here'), findsOneWidget);
      var waypoints = await stored(tester);
      expect(waypoints.single.kind, WaypointKind.marked);
      expect(waypoints.single.latitude, walkFix(0).latitude);
      expect(waypoints.single.accuracy, 3);
      expect(waypoints.single.fixTime, walkFix(0).time);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name (optional)'),
        'Spring',
      );
      await act(tester, () async => tester.tap(find.text('Save')));
      await tester.pumpAndSettle();
      expect(find.text('Marked here'), findsNothing);
      waypoints = await stored(tester);
      expect(waypoints.single.name, 'Spring');
      await cleanUp(tester);
    });

    testWidgets('a mark from an old fix says so, and can be deleted', (
      tester,
    ) async {
      await show(tester);
      await tap(tester, 'Expedition');
      await act(tester, () async => location.emit(walkFix(0)));
      now = t0.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 1));

      await act(tester, () async => tester.tap(markButton()));
      await tester.pumpAndSettle();
      expect(
        find.text('Marked at the last position known, 20 s ago.'),
        findsOneWidget,
      );
      await act(tester, () async => tester.tap(find.text('Delete')));
      await tester.pumpAndSettle();
      expect(await stored(tester), isEmpty);
      await cleanUp(tester);
    });

    testWidgets('there is nothing to mark while paused', (tester) async {
      await show(tester);
      await tap(tester, 'Expedition');
      await act(tester, () async => location.emit(walkFix(0)));
      expect(markButton(), findsOneWidget);
      await tap(tester, 'Pause');
      expect(markButton(), findsNothing);
      await cleanUp(tester);
    });
  });

  group('elevation (X3)', () {
    Fix high(int second, double altitude) => Fix(
      time: t0.add(Duration(seconds: second)),
      latitude: walkFix(second).latitude,
      longitude: 77,
      accuracy: 3,
      altitude: altitude,
      altitudeAccuracy: 4,
    );

    testWidgets('an expedition shows climb once the GPS gives height', (
      tester,
    ) async {
      await show(tester);
      await tap(tester, 'Expedition');
      await act(tester, () async => location.emit(walkFix(0)));
      expect(find.textContaining('Climb'), findsNothing);

      await act(tester, () async => location.emit(high(2, 2000)));
      expect(find.text('Climb 0 m · Descent 0 m'), findsOneWidget);
      await cleanUp(tester);
    });

    testWidgets('the road readout stays speed, distance and time', (
      tester,
    ) async {
      await show(tester);
      await tap(tester, 'Road journey');
      await act(tester, () async => location.emit(high(0, 2000)));
      expect(find.textContaining('Climb'), findsNothing);
      await cleanUp(tester);
    });
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

      // Altitude when the GPS gives one, with its own accuracy.
      await act(
        tester,
        () async => location.emit(
          Fix(
            time: t0.add(const Duration(seconds: 1)),
            latitude: 32,
            longitude: 77,
            accuracy: 3,
            altitude: 2240.4,
            altitudeAccuracy: 8,
          ),
        ),
      );
      expect(
        find.text('32.00000° N, 77.00000° E ±3 m · altitude 2240 m ±8 m'),
        findsOneWidget,
      );

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
    expect(find.text('Paused'), findsOneWidget);
    await tap(tester, 'Resume');
    expect(find.text('Recording'), findsOneWidget);

    await tap(tester, 'End journey');
    expect(find.text('End this journey?'), findsOneWidget);
    await tap(tester, 'Keep going');
    expect(find.text('Recording'), findsOneWidget);

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

    expect(find.text('Stopped'), findsOneWidget);
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
      expect(find.text('Recording'), findsOneWidget);
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
