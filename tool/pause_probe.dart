// Device-only entrypoint. Install under a separate applicationId; never over
// the owner's app. Use local Firebase emulators, forwarded by adb reverse.
// The journey receives ONLY SimulatedLocation fixes. Optional native service
// probing discards every platform fix; it never enters storage, sharing/logs.
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tripping/app/record_screen.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/app/system_access.dart';
import 'package:tripping/group/firebase_relay.dart';
import 'package:tripping/group/group_sync.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/main.dart' show TrippingApp;
import 'package:tripping/map/journey_map.dart';
import 'package:tripping/map/map_activity.dart';
import 'package:tripping/recording/geolocator_location.dart';
import 'package:tripping/recording/location_source.dart';
import 'package:tripping/recording/recorder.dart';
import 'package:tripping/recording/simulated_location.dart';

class ProbeRelay extends FirebaseRelay {
  bool configured = false;
  int epoch = 0;
  @override
  Future<void> suspend() async {
    epoch++;
    await super.suspend();
  }

  @override
  Future<void> resume() async {
    final current = ++epoch;
    if (!configured) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIza00000000000000000000000000000000000',
          appId: '1:000000000000:android:00000000000000000000000000000000',
          messagingSenderId: '000000000000',
          projectId: 'demo-tripping-rules',
          databaseURL:
              'https://demo-tripping-rules-default-rtdb.firebaseio.com',
        ),
      );
      await FirebaseAuth.instance.useAuthEmulator(
        '127.0.0.1',
        9099,
        automaticHostMapping: false,
      );
      FirebaseDatabase.instance.useDatabaseEmulator(
        '127.0.0.1',
        9000,
        automaticHostMapping: false,
      );
      configured = true;
    }
    if (current == epoch) await super.resume();
  }
}

class ProbeLocation implements LocationSource {
  final synthetic = SimulatedLocation(origin: (12.9763, 77.5929));
  static const native = bool.fromEnvironment('PAUSE_PROBE_NATIVE');
  @override
  Future<LocationAccess> requestAccess() async => LocationAccess.granted;
  @override
  Future<void> openSettingsFor(LocationAccess problem) async {}
  @override
  Future<Fix?> lastKnown() => synthetic.lastKnown();
  @override
  Stream<Fix> watch(JourneyMode mode) {
    StreamSubscription<Fix>? service;
    StreamSubscription<Fix>? simulated;
    late StreamController<Fix> out;
    out = StreamController<Fix>(
      onListen: () {
        if (native) {
          // Exercise real service/sensor/wake-lock cancellation only. Platform
          // fixes are deliberately ignored, including all coordinate fields.
          service = const GeolocatorLocation()
              .watch(mode)
              .listen((_) {}, onError: (Object _) {});
        }
        simulated = synthetic.watch(mode).listen(out.add);
      },
      onCancel: () async {
        await simulated?.cancel();
        await service?.cancel();
      },
    );
    return out.stream;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final store = JourneyStore.file(File('${documents.path}/journeys.sqlite'));
  final settings = await Settings.open(File('${documents.path}/settings.json'));
  await settings.setName('Ravi');
  final location = ProbeLocation();
  final recorder = await Recorder.open(store, location);
  // Only the isolated probe's new recording gets a fictional test group.
  recorder.changes.listen((state) async {
    if (state is Recording &&
        await store.membershipOf(state.journey.id) == null) {
      final invite = Invite.create(state.journey.uuid, 'Ravi');
      await store.saveMembership(
        state.journey.id,
        groupId: invite.groupId,
        secret: invite.secret,
        role: GroupRole.creator,
        at: DateTime.now().toUtc(),
      );
    }
  });
  final group = GroupSync(ProbeRelay());
  const MethodChannel('tripping/pause_probe').setMethodCallHandler((
    call,
  ) async {
    switch (call.method) {
      case 'start':
        await recorder.start(JourneyMode.expedition);
      case 'pause':
        await recorder.pause();
        await group.suspend();
      case 'resume':
        await recorder.resume();
      case 'end':
        await recorder.end();
        await group.stop();
      case 'pauseSharing':
        final state = recorder.state as Recording;
        await group.suspend();
        await settings.setSharingPaused(state.journey.uuid, true);
      case 'resumeSharing':
        final state = recorder.state as Recording;
        await settings.setSharingPaused(state.journey.uuid, false);
      default:
        throw PlatformException(code: 'unknown-command');
    }
    await recorder.settled();
  });
  runApp(
    TrippingApp(
      home: RecordScreen(
        recorder: recorder,
        location: location,
        system: const ChannelSystemAccess(),
        settings: settings,
        group: group,
        waypoints: store,
        onMapNetworkChanged: MapActivity.setNetworkEnabled,
        mapBuilder: (state, now) => JourneyMap(
          state: state,
          store: store,
          now: now,
          group: group.status,
        ),
      ),
    ),
  );
}
