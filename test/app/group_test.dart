import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tripping/app/record_screen.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/recording/recorder.dart';

import '../support/fakes.dart';

const hostGroup = '0192f5a4-3b1c-7d2e-8f00-123456789abc';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late JourneyStore store;
  late FakeLocation location;
  late FakeSystemAccess system;
  late Settings settings;
  late Recorder recorder;
  late Directory dir;
  late List<String> shared;
  Invite? scanned;
  final asha = Invite.create(hostGroup, 'Asha');

  setUp(() async {
    store = JourneyStore(NativeDatabase.memory());
    location = FakeLocation();
    system = FakeSystemAccess();
    dir = Directory.systemTemp.createTempSync('tripping_group');
    settings = await Settings.open(File('${dir.path}/settings.json'));
    shared = [];
    scanned = null;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> act(WidgetTester tester, Future<void> Function() work) async {
    await tester.runAsync(() async {
      await work();
      await recorder.settled();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  Future<void> show(WidgetTester tester) async {
    await tester.runAsync(() async {
      recorder = await Recorder.open(store, location, clock: () => t0);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingTheme(Brightness.light),
        home: RecordScreen(
          recorder: recorder,
          location: location,
          system: system,
          mapBuilder: (_, _) => const SizedBox.expand(),
          waypoints: store,
          settings: settings,
          // Stands in for the camera: "sees" [scanned] at once.
          scannerBuilder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.pop(context, scanned),
              child: const Text('fake scan'),
            ),
          ),
          shareText: (text) async => shared.add(text),
          clock: () => t0,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await recorder.close();
      await store.close();
    });
  }

  /// Runs a second of frames: page transitions finish, while a waiting-for-
  /// GPS spinner (which never settles) keeps turning.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets real file and database work run, frame by frame: saving the
  /// name or the participant id happens on the real clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await frames(tester);
  }

  Future<void> giveName(WidgetTester tester, String name) async {
    expect(find.text('Your name for groups'), findsOneWidget);
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text('Save'));
    await settle(tester);
  }

  /// Taps [label] where the work it starts needs real async (the store).
  Future<void> tapReal(WidgetTester tester, String label) async {
    await act(tester, () async => tester.tap(find.text(label)));
    await settle(tester);
  }

  void pasteboard(String text) {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') return {'text': text};
          return null;
        });
  }

  testWidgets('inviting asks a name once, and shares one stable link', (
    tester,
  ) async {
    await show(tester);
    await act(tester, () async => tester.tap(find.text('Expedition')));
    await act(tester, () async => location.emit(walkFix(0)));

    await tester.tap(find.text('Invite companions'));
    await frames(tester);
    await giveName(tester, 'Asha');
    await settle(tester);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('Not connected yet'), findsOneWidget);
    await tester.tap(find.text('Share invite link'));
    final journey = (recorder.state as Recording).journey;
    final first = Invite.find(shared.single)!;
    expect((first.groupId, first.hostName), (journey.uuid, 'Asha'));

    await tester.pageBack();
    await frames(tester);
    expect(find.text('Your group'), findsOneWidget);
    expect(
      find.text('Not connected yet: positions are not shared'),
      findsOneWidget,
    );

    // Again: no second name prompt, the same secret.
    await tester.tap(find.text('Invite'));
    await frames(tester);
    await settle(tester);
    expect(find.text('Your name for groups'), findsNothing);
    await tester.tap(find.text('Share invite link'));
    expect(Invite.find(shared.last), first);
    expect(settings.name.value, 'Asha');
    await cleanUp(tester);
  });

  testWidgets('a pasted invite joins offline, starting the journey', (
    tester,
  ) async {
    pasteboard('Join my group on Tripping:\n${asha.link}');
    await show(tester);
    await tester.tap(find.text('Join a group'));
    await frames(tester);
    await giveName(tester, 'Ravi');
    await settle(tester);
    await tester.tap(find.text('Paste invite link'));
    await frames(tester);
    expect(find.text("Join Asha's group?"), findsOneWidget);
    expect(find.textContaining('Not connected yet'), findsOneWidget);

    await tapReal(tester, 'Join and start an expedition');
    expect(recorder.state, isA<Recording>());
    final journey = (recorder.state as Recording).journey;
    expect(journey.mode, JourneyMode.expedition);
    final row = await tester.runAsync(() => store.membershipOf(journey.id));
    expect(
      (row?.groupId, row?.secret, row?.role, row?.hostName),
      (hostGroup, asha.secret, GroupRole.member, 'Asha'),
    );
    await tester.pump();
    expect(find.text("In Asha's group"), findsOneWidget);
    // Membership is never shown as connection.
    expect(find.textContaining('Connected'), findsNothing);
    expect(find.textContaining('online'), findsNothing);
    await cleanUp(tester);
  });

  testWidgets('a scanned invite joins the journey under way', (tester) async {
    scanned = asha;
    await tester.runAsync(() => settings.setName('Ravi'));
    await show(tester);
    await act(tester, () async => tester.tap(find.text('Road journey')));
    await tester.tap(find.text('Join a group').last);
    await frames(tester);
    await settle(tester);
    await tester.tap(find.text('Scan invite code'));
    await frames(tester);
    await tester.tap(find.text('fake scan'));
    await frames(tester);
    await tapReal(tester, 'Join with this journey');
    await act(tester, () async {});
    expect(find.text("In Asha's group"), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('a link that opens the app goes to the join screen', (
    tester,
  ) async {
    await tester.runAsync(() => settings.setName('Ravi'));
    await show(tester);
    system.open(asha.link);
    await settle(tester);
    expect(find.text("Join Asha's group?"), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('copied text without an invite is refused, plainly', (
    tester,
  ) async {
    pasteboard('see you at the trailhead');
    await tester.runAsync(() => settings.setName('Ravi'));
    await show(tester);
    await tester.tap(find.text('Join a group'));
    await frames(tester);
    await settle(tester);
    await tester.tap(find.text('Paste invite link'));
    await frames(tester);
    expect(find.textContaining('holds no Tripping invite'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('scanning your own invite does not join it', (tester) async {
    await tester.runAsync(() => settings.setName('Asha'));
    await show(tester);
    await act(tester, () async => tester.tap(find.text('Expedition')));
    final journey = (recorder.state as Recording).journey;
    scanned = Invite.create(journey.uuid, 'Asha');
    await tester.tap(find.text('Join a group').last);
    await frames(tester);
    await settle(tester);
    await tester.tap(find.text('Scan invite code'));
    await frames(tester);
    await tester.tap(find.text('fake scan'));
    await frames(tester);
    await tapReal(tester, 'Join with this journey');
    expect(find.text('That is your own group.'), findsOneWidget);
    expect(await tester.runAsync(() => store.membershipOf(journey.id)), isNull);
    await cleanUp(tester);
  });
}
