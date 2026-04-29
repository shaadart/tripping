import 'dart:async';
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
import 'package:tripping/group/group_keys.dart';
import 'package:tripping/group/group_sync.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/group/relay.dart';
import 'package:tripping/group/sharing.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/recording/recorder.dart';

import '../support/fake_relay.dart';
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
  GroupSync? group;
  final mapNetwork = <bool>[];
  final asha = Invite.create(hostGroup, 'Asha');

  setUp(() async {
    store = JourneyStore(NativeDatabase.memory());
    location = FakeLocation();
    system = FakeSystemAccess();
    dir = Directory.systemTemp.createTempSync('tripping_group');
    settings = await Settings.open(File('${dir.path}/settings.json'));
    shared = [];
    scanned = null;
    group = null;
    mapNetwork.clear();
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
          group: group,
          onMapNetworkChanged: (enabled) async {
            mapNetwork.add(enabled);
          },
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
    // It lives as long as the app; a test ends it (its timer at once).
    unawaited(group?.stop());
    await tester.pump();
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
    expect(find.textContaining('Positions are sealed'), findsOneWidget);
    await tester.tap(find.text('Share invite link'));
    final journey = (recorder.state as Recording).journey;
    final first = Invite.find(shared.single)!;
    expect((first.groupId, first.hostName), (journey.uuid, 'Asha'));

    await tester.pageBack();
    await frames(tester);
    expect(find.text('Your group'), findsOneWidget);
    expect(
      find.text('Not connected: positions are not shared'),
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
    expect(find.textContaining('even without a connection'), findsOneWidget);

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

  testWidgets('reachable, and who was heard when: nothing more', (
    tester,
  ) async {
    final relay = FakeRelay()..reachable = true;
    group = GroupSync(relay, clock: () => t0);
    await tester.runAsync(() => settings.setName('Ravi'));
    await show(tester);
    await act(tester, () async => tester.tap(find.text('Expedition')));
    await act(tester, () async => location.emit(walkFix(0)));
    final journey = (recorder.state as Recording).journey;
    await tester.runAsync(
      () => store.saveMembership(
        journey.id,
        groupId: asha.groupId,
        secret: asha.secret,
        role: GroupRole.member,
        hostName: 'Asha',
        at: t0,
      ),
    );
    await settle(tester);
    expect(
      find.text('Connected · sharing your position with the group'),
      findsOneWidget,
    );
    expect(relay.published, hasLength(1), reason: 'said "here" on joining');

    relay.changes.add([]);
    await settle(tester);
    expect(find.text('No one else has joined yet'), findsOneWidget);

    // Asha's entry reached the relay 10 s before now, whose clock runs 2 s
    // ahead of this phone's.
    final keys = await tester.runAsync(() => GroupKeys.derive(asha.secret));
    // 1 km north of this phone's fix, from 15 s before now.
    final ashaSaid = Shared(
      name: 'Asha',
      phase: JourneyPhase.recording,
      mode: JourneyMode.road,
      fix: Fix(
        time: t0.subtract(const Duration(seconds: 15)),
        latitude: 32 + 1000 / metersPerDegree,
        longitude: 77,
        accuracy: 5,
      ),
    );
    final box = await tester.runAsync(
      () => keys!.seal(ashaSaid.toMessage(), 'a'),
    );
    relay.changes.add([
      RelayEntry(
        participant: 'a',
        seq: 3,
        at: t0.subtract(const Duration(seconds: 10)),
        box: box!,
      ),
    ]);
    await settle(tester);
    expect(find.text('Asha · 1.0 km N · 15 s ago'), findsOneWidget);

    relay.reach(false);
    await settle(tester);
    expect(
      find.textContaining('· sharing resumes when the connection returns'),
      findsOneWidget,
    );
    expect(find.textContaining('Offline since'), findsOneWidget);
    // Still said with its age, never as current.
    expect(find.text('Asha · 1.0 km N · 15 s ago'), findsOneWidget);

    // Leaving: confirmed, the entries go, the journey goes on.
    relay.reach(true);
    await settle(tester);
    await tester.tap(find.text('Leave group'));
    await frames(tester);
    expect(find.text('Leave the group?'), findsOneWidget);
    await tapReal(tester, 'Leave');
    expect(relay.left, 1);
    expect(find.text('Invite companions'), findsOneWidget);
    expect(recorder.state, isA<Recording>());
    await cleanUp(tester);
  });
  testWidgets('paused cold open does not start GPS, group or map network', (
    tester,
  ) async {
    final relay = FakeRelay()..reachable = true;
    group = GroupSync(relay);
    await tester.runAsync(() async {
      final journey = await store.startJourney(JourneyMode.expedition, at: t0);
      await store.pause(journey.id, at: t0);
      await store.saveMembership(
        journey.id,
        groupId: asha.groupId,
        secret: asha.secret,
        role: GroupRole.member,
        hostName: 'Asha',
        at: t0,
      );
    });
    await show(tester);
    await settle(tester);
    expect(recorder.state, isA<Paused>());
    expect(location.listening, isFalse);
    expect(relay.resumptions, 0);
    expect(relay.opened, isEmpty);
    expect(mapNetwork, [false]);
    final suspensions = relay.suspensions;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(relay.suspensions, greaterThan(suspensions));
    expect(relay.resumptions, 0);
    expect(
      find.textContaining('Journey paused · group updates stopped'),
      findsOneWidget,
    );
    await cleanUp(tester);
  });

  testWidgets(
    'sharing pause keeps recording; full pause also stops map updates',
    (tester) async {
      final relay = FakeRelay()..reachable = true;
      group = GroupSync(relay, clock: () => t0);
      await tester.runAsync(() => settings.setName('Ravi'));
      await show(tester);
      await tapReal(tester, 'Expedition');
      await act(tester, () async => location.emit(walkFix(0)));
      final journey = (recorder.state as Recording).journey;
      await tester.runAsync(
        () => store.saveMembership(
          journey.id,
          groupId: asha.groupId,
          secret: asha.secret,
          role: GroupRole.member,
          hostName: 'Asha',
          at: t0,
        ),
      );
      await settle(tester);
      await tester.ensureVisible(find.text('Pause sharing'));
      await tapReal(tester, 'Pause sharing');
      expect(recorder.state, isA<Recording>());
      expect(location.listening, isTrue);
      expect(settings.sharingPaused(journey.uuid), isTrue);
      expect(group!.status.value?.suspended, isTrue);
      expect(mapNetwork.last, isTrue);
      final sent = relay.published.length;
      relay.reach(false);
      relay.reach(true);
      await act(tester, () async => location.emit(walkFix(3)));
      expect(relay.published, hasLength(sent));
      await tester.ensureVisible(find.text('Pause'));
      await tapReal(tester, 'Pause');
      expect(recorder.state, isA<Paused>());
      expect(location.listening, isFalse);
      expect(mapNetwork.last, isFalse);
      await tester.ensureVisible(find.text('Resume'));
      await tapReal(tester, 'Resume');
      expect(recorder.state, isA<Recording>());
      expect(
        group!.status.value?.suspended,
        isTrue,
        reason: 'full resume respects sharing-only choice',
      );
      await tester.ensureVisible(find.text('Resume sharing'));
      await tapReal(tester, 'Resume sharing');
      expect(settings.sharingPaused(journey.uuid), isFalse);
      expect(relay.published.length, greaterThan(sent));
      await cleanUp(tester);
    },
  );

  testWidgets(
    'ordinary backgrounding keeps recording but disables map activity',
    (tester) async {
      await show(tester);
      await tapReal(tester, 'Expedition');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await act(tester, () async => location.emit(walkFix(0)));
      expect(recorder.state, isA<Recording>());
      expect(location.listening, isTrue);
      expect(mapNetwork.last, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(mapNetwork.last, isTrue);
      await cleanUp(tester);
    },
  );
}
