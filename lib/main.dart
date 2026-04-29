import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart'
    show LatLng, setHttpHeaders, setOfflineMaxConcurrentRequests;
import 'package:path_provider/path_provider.dart';

import 'app/frame_stats.dart';
import 'app/history_screen.dart';
import 'app/offline_maps_screen.dart';
import 'app/record_screen.dart';
import 'app/settings.dart';
import 'app/identity_screen.dart';
import 'app/share_gpx.dart';
import 'app/system_access.dart';
import 'app/theme.dart';
import 'bench/long_journey_bench.dart';
import 'history/journey_history.dart';
import 'journey/journey_store.dart';
import 'map/area_map.dart';
import 'map/journey_map.dart';
import 'map/map_tiles.dart';
import 'map/map_activity.dart';
import 'map/offline_area.dart';
import 'map/offline_maps.dart';
import 'map/track_map.dart';
import 'recording/geolocator_location.dart';
import 'recording/location_source.dart';
import 'places/place_search.dart';
import 'group/firebase_relay.dart';
import 'group/group_housekeeping.dart';
import 'group/group_sync.dart';
import 'recording/raw_fix_log.dart';
import 'recording/simulated_location.dart';
import 'relay/relay_spike.dart';
import 'recording/recorder.dart';
import 'routing/route_planner.dart';
import 'routing/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (FrameStats.enabled) FrameStats.start();
  // S1 test builds only; a failure must not keep the app from opening.
  if (RelaySpike.enabled) {
    unawaited(
      RelaySpike.start().catchError(
        (Object error) => debugPrint('S1 start failed: $error'),
      ),
    );
  }
  final highSun = ValueNotifier(false);
  runApp(TrippingApp(home: await _openHome(highSun), highSun: highSun));
}

/// The composition root: builds the long-lived objects once. Opening the
/// recorder also recovers a journey interrupted by a process death.
Future<Widget> _openHome(ValueNotifier<bool> highSun) async {
  try {
    final documents = await getApplicationDocumentsDirectory();
    final settings = await Settings.open(
      File('${documents.path}/settings.json'),
    );
    highSun.value = settings.highSun.value;
    settings.highSun.addListener(() => highSun.value = settings.highSun.value);
    // A bench build measures on its own database, never the owner's.
    final file = File(
      '${documents.path}/'
      '${LongJourneyBench.enabled ? LongJourneyBench.databaseName : 'journeys.sqlite'}',
    );
    final store = JourneyStore.file(file);
    if (LongJourneyBench.enabled) await LongJourneyBench.run(store, file);
    // A simulated test build makes up its positions and never reads the
    // phone's (E-037); every other build reads the GPS.
    LocationSource location = SimulatedLocation.enabled
        ? SimulatedLocation.fromSpec(SimulatedLocation.spec)
        : const GeolocatorLocation();
    if (kDebugMode) {
      location = RawFixLog(location, File('${documents.path}/raw_fixes.jsonl'));
    }
    final recorder = await Recorder.open(store, location);
    MapLibreOfflineMaps? offline;
    try {
      // Restore before allowing any map traffic. Map failures cannot hide
      // the saved journey or prevent using its recorder controls.
      await MapActivity.setNetworkEnabled(recorder.state is Idle);
      final tiles = await MapTiles.open(documents, settings);
      MapTiles.current = tiles;
      offline = MapLibreOfflineMaps(tiles);
      await setHttpHeaders({'User-Agent': MapTiles.userAgent});
      await setOfflineMaxConcurrentRequests(
        maxRequestsPerHost: OfflineLimits.parallelRequests,
      );
      unawaited(offline.list().catchError((Object _) => <OfflineMap>[]));
    } on Object {
      offline = null;
    }
    final maps = offline;
    // Open-source search and routing over OpenStreetMap (D-026).
    final planner = RoutePlanner(store, ValhallaRouter());
    // Positions shared with the journey's group (G2, G3; D-034, D-037).
    final relay = FirebaseRelay();
    late final GroupSync group;
    var tidied = false;
    group = GroupSync(
      relay,
      onConnected: () async {
        if (tidied) return;
        tidied = true;
        await tidyGroups(
          store,
          relay,
          now: DateTime.now().toUtc(),
          shouldContinue: () =>
              recorder.state is Recording &&
              group.status.value?.suspended != true,
        );
      },
    );
    final screen = RecordScreen(
      recorder: recorder,
      location: location,
      system: const ChannelSystemAccess(),
      mapBuilder: (state, now) => maps == null
          ? const Center(
              child: Text('Map unavailable. Your journey stays saved.'),
            )
          : JourneyMap(
              state: state,
              store: store,
              now: now,
              planner: planner,
              group: group.status,
              identity: settings.identity.value,
            ),
      places: PhotonSearch(),
      planner: planner,
      settings: settings,
      group: group,
      onMapNetworkChanged: MapActivity.setNetworkEnabled,
      waypoints: store,
      onToggleHighSun: () => settings.setHighSun(!settings.highSun.value),
      savedOffline: maps?.saved,
      offlineMapsBuilder: maps == null
          ? null
          : (_) => OfflineMapsScreen(
              maps: maps,
              areaMapBuilder: (onArea) =>
                  AreaMap(onArea: onArea, start: _lastKnown(recorder.state)),
            ),
      historyBuilder: (_) {
        final history = JourneyHistory(store);
        return HistoryScreen(
          history: history,
          trackMapBuilder: (track, waypoints, route) => TrackMap(
            track: track,
            waypoints: waypoints,
            route: route,
            onDrawn: LongJourneyBench.enabled
                ? LongJourneyBench.detailDrawn
                : null,
          ),
          onExport: (past) => shareGpx(history, past),
        );
      },
    );
    // Never hide an existing paused/interrupted journey behind onboarding.
    return recorder.state is Idle
        ? IdentityGate(settings: settings, child: screen)
        : screen;
  } catch (error) {
    return StartupFailure(error: error);
  }
}

/// Where the phone was last known to be, to open the area picker there.
LatLng? _lastKnown(RecorderState state) {
  final fix = switch (state) {
    Recording(:final latestFix?) => latestFix,
    Recording(:final progress) ||
    Paused(:final progress) ||
    Interrupted(:final progress) => progress.lastFix,
    Idle() => null,
  };
  return fix == null ? null : LatLng(fix.latitude, fix.longitude);
}

class TrippingApp extends StatelessWidget {
  const TrippingApp({super.key, required this.home, this.highSun});

  final Widget home;

  /// When on, the high-sun look replaces both the light and the dark one.
  final ValueListenable<bool>? highSun;

  static final _off = ValueNotifier(false);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: highSun ?? _off,
      builder: (context, sun, _) => MaterialApp(
        title: 'Tripping',
        theme: trippingLook(sun ? Look.highSun : Look.light),
        darkTheme: trippingLook(sun ? Look.highSun : Look.dark),
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );
  }
}

/// Shown when the journey storage cannot be opened. Nothing was changed.
class StartupFailure extends StatelessWidget {
  const StartupFailure({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tripping can’t open its storage',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Nothing was recorded or changed. Restarting the phone may '
                'help.\n\n$error',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
