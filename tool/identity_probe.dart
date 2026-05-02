// Test-only entrypoint: separate applicationId, synthetic positions/people,
// in-memory relay. Never install over a personal Tripping installation.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show setHttpHeaders;
import 'package:tripping/app/offline_maps_screen.dart';
import 'package:tripping/map/area_map.dart';
import 'package:tripping/map/map_tiles.dart';
import 'package:tripping/map/offline_maps.dart';
import 'package:tripping/places/place_search.dart';
import 'package:tripping/routing/route_planner.dart';
import 'package:tripping/routing/router.dart';
import 'package:tripping/app/history_screen.dart';
import 'package:tripping/app/identity_screen.dart';
import 'package:tripping/app/record_screen.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/app/system_access.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/group/group_sync.dart';
import 'package:tripping/group/identity.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/group/sharing.dart';
import 'package:tripping/history/journey_history.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/map/journey_map.dart';
import 'package:tripping/map/map_activity.dart';
import 'package:tripping/map/track_map.dart';
import 'package:tripping/recording/recorder.dart';
import 'package:tripping/recording/simulated_location.dart';

import '../test/support/fake_relay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final settings = await Settings.open(File('${documents.path}/settings.json'));
  final store = JourneyStore.file(File('${documents.path}/journeys.sqlite'));
  final location = SimulatedLocation(origin: (12.9763, 77.5929), speed: 0.6);
  final recorder = await Recorder.open(store, location);
  final group = GroupSync(FakeRelay());
  // Search, routing and offline maps as in the app, so their screens can
  // be checked; positions stay synthetic.
  final planner = RoutePlanner(store, ValhallaRouter());
  OfflineMaps? offline;
  try {
    final tiles = await MapTiles.open(documents, settings);
    MapTiles.current = tiles;
    offline = MapLibreOfflineMaps(tiles);
    await setHttpHeaders({'User-Agent': MapTiles.userAgent});
  } on Object {
    offline = null;
  }
  final maps = offline;
  final look = ValueNotifier(Look.light);
  final textScale = ValueNotifier(1.0);
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
      case 'dark':
        look.value = Look.dark;
      case 'light':
        look.value = Look.light;
      case 'sun':
        look.value = Look.highSun;
      case 'offline':
        await MapActivity.setNetworkEnabled(false);
      case 'largeText':
        textScale.value = 2;
      case 'normalText':
        textScale.value = 1;
      case 'companions':
        final journey = (recorder.state as Recording).journey;
        final invite = Invite.create(journey.uuid, 'Ravi');
        if (await store.membershipOf(journey.id) == null) {
          await store.saveMembership(
            journey.id,
            groupId: invite.groupId,
            secret: invite.secret,
            role: GroupRole.creator,
            at: DateTime.now().toUtc(),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final now = DateTime.now().toUtc();
        final here = (recorder.state as Recording).progress.lastFix!;
        group.status.value = GroupStatus(
          companions: [
            for (final (name, colour, shape, lat, lon, seconds) in [
              (
                'Asha Rao',
                IdentityColour.moss,
                MarkerShape.rosette,
                0.00065,
                -0.00085,
                2,
              ),
              (
                'Meera',
                IdentityColour.plum,
                MarkerShape.reed,
                0.00065,
                0.00085,
                60,
              ),
              (
                'Noor',
                IdentityColour.ochre,
                MarkerShape.gate,
                -0.00065,
                -0.00085,
                600,
              ),
              (
                'Tom',
                IdentityColour.slate,
                MarkerShape.tablet,
                -0.00065,
                0.00085,
                5,
              ),
            ])
              Companion(
                participant: name,
                heardAt: now,
                shared: Shared(
                  name: name,
                  colour: colour,
                  shape: shape,
                  phase: JourneyPhase.recording,
                  mode: JourneyMode.expedition,
                  fix: Fix(
                    time: now.subtract(Duration(seconds: seconds)),
                    latitude: here.latitude + lat,
                    longitude: here.longitude + lon,
                    accuracy: 5,
                  ),
                ),
              ),
          ],
        );
      default:
        throw PlatformException(code: 'unknown-command');
    }
    await recorder.settled();
  });
  final screen = RecordScreen(
    recorder: recorder,
    location: location,
    system: const ChannelSystemAccess(),
    settings: settings,
    group: group,
    waypoints: store,
    onMapNetworkChanged: MapActivity.setNetworkEnabled,
    places: PhotonSearch(),
    planner: planner,
    offlineMapsBuilder: maps == null
        ? null
        : (_) => OfflineMapsScreen(
            maps: maps,
            areaMapBuilder: (onArea) => AreaMap(onArea: onArea),
          ),
    historyBuilder: (_) => HistoryScreen(
      history: JourneyHistory(store),
      trackMapBuilder: (track, waypoints, route) =>
          TrackMap(track: track, waypoints: waypoints, route: route),
    ),
    mapBuilder: (state, now) => JourneyMap(
      state: state,
      now: now,
      store: store,
      planner: planner,
      group: group.status,
      identity: settings.identity.value,
    ),
  );
  final home = recorder.state is Idle
      ? IdentityGate(settings: settings, child: screen)
      : screen;
  runApp(
    ListenableBuilder(
      listenable: Listenable.merge([look, textScale]),
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: trippingLook(look.value),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale.value)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
}
