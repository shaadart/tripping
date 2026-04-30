// Isolated rendering fixture. Synthetic park geometry, fictional names,
// in-memory location/system facts; no native GPS, Firebase, search or routing.
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tripping/app/record_screen.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/group/identity.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/map/journey_map.dart';
import 'package:tripping/map/map_activity.dart';
import 'package:tripping/map/map_tiles.dart';
import 'package:tripping/map/track_map.dart';
import 'package:tripping/places/polyline.dart';
import 'package:tripping/recording/recorder.dart';
import 'package:tripping/routing/route_planner.dart';
import 'package:tripping/routing/router.dart';

import '../test/support/fakes.dart';

const _stressWay = [
  (12.9748, 77.5915),
  (12.9758, 77.5915),
  (12.9758, 77.5932),
  (12.9772, 77.5932),
  (12.9772, 77.5915),
  (12.9780, 77.5915),
];
const _stressGround = [
  [
    (12.9748, 77.5915),
    (12.9758, 77.5915),
    (12.9758, 77.5924),
    (12.9765, 77.5924),
    (12.9765, 77.5917),
  ],
  [
    (12.9770, 77.5917),
    (12.9767, 77.5932),
    (12.9758, 77.5932),
    (12.9758, 77.5924),
    (12.9752, 77.5924),
  ],
];

const _way = [
  (12.9748, 77.5915),
  (12.9750, 77.59155),
  (12.97525, 77.59167),
  (12.97545, 77.59186),
  (12.97565, 77.59205),
  (12.97586, 77.59218),
  (12.9761, 77.59228),
  (12.97635, 77.5923),
  (12.97658, 77.59234),
  (12.97678, 77.59245),
  (12.97695, 77.59264),
  (12.9771, 77.59285),
  (12.9773, 77.59302),
  (12.97752, 77.59313),
  (12.97775, 77.5932),
  (12.978, 77.59324),
];
final _ground = [
  _way.take(7).toList(),
  [_way[8], _way[9], _way[10], _way[11]],
];

class _Fixture {
  _Fixture(
    this.store,
    this.recorder,
    this.location,
    this.journey,
    this.route,
    this.here,
  );
  final JourneyStore store;
  final Recorder recorder;
  final FakeLocation location;
  final JourneyRow journey;
  final RouteRow route;
  final (double, double) here;
  bool approximate = false;
  late final planner = RoutePlanner(store, _NoRouter());
  Future<void> fix() async {
    if (!location.listening) return;
    final at = here;
    location.emit(
      Fix(
        time: DateTime.now().toUtc(),
        latitude: at.$1,
        longitude: at.$2,
        accuracy: approximate ? 140 : 5,
        speed: 0,
        heading: 0,
      ),
    );
    await recorder.settled();
  }
}

class _NoRouter implements RouteSource {
  @override
  Future<PlannedRoute> route(
    (double, double) from,
    (double, double) to,
    JourneyMode mode, {
    required DateTime at,
  }) async => throw const RouteError('Synthetic rendering fixture');
}

Future<_Fixture> _seed(
  Directory dir,
  JourneyMode mode, {
  List<(double, double)> way = _way,
  List<List<(double, double)>>? ground,
}) async {
  ground ??= _ground;
  final now = DateTime.now().toUtc();
  final store = JourneyStore.file(
    File(
      '${dir.path}/${now.microsecondsSinceEpoch}-${mode.name}-map-probe.sqlite',
    ),
  );
  final journey = await store.startJourney(
    mode,
    at: now.subtract(const Duration(minutes: 20)),
  );
  var second = 0;
  for (final (index, segment) in ground.indexed) {
    if (index > 0) {
      await store.resume(
        journey.id,
        at: now.subtract(Duration(seconds: 1200 - second)),
      );
    }
    for (final at in segment) {
      await store.append(
        journey.id,
        Fix(
          time: now.subtract(Duration(seconds: 1200 - second)),
          latitude: at.$1,
          longitude: at.$2,
          accuracy: 5,
        ),
      );
      second += 60;
    }
    await store.pause(
      journey.id,
      at: now.subtract(Duration(seconds: 1200 - second)),
    );
    second += 120;
  }
  await store.setDestination(
    journey.id,
    name: 'Cedar Camp',
    latitude: way.last.$1,
    longitude: way.last.$2,
  );
  await store.saveRoute(
    journey.id,
    kind: RouteKind.road,
    provider: 'synthetic fixture',
    computedAt: now,
    meters: 700,
    seconds: 500,
    geometry: encodePolyline(way),
  );
  for (final (kind, name, at) in [
    (WaypointKind.marked, 'Rest stop', ground.first.last),
    (WaypointKind.planned, 'Lookout', way[way.length - 3]),
  ]) {
    await store.addWaypoint(
      journey.id,
      kind: kind,
      at: now,
      latitude: at.$1,
      longitude: at.$2,
      name: name,
    );
  }
  final location = FakeLocation();
  final recorder = await Recorder.open(store, location);
  await recorder.resume();
  final fixture = _Fixture(
    store,
    recorder,
    location,
    journey,
    (await store.routeOf(journey.id))!,
    ground.last.last,
  );
  await fixture.fix();
  return fixture;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final settings = await Settings.open(File('${dir.path}/settings.json'));
  await settings.setIdentity(
    const MapIdentity(
      name: 'Ravi Mehta',
      colour: IdentityColour.river,
      shape: MarkerShape.gate,
    ),
  );
  final tiles = await MapTiles.open(dir, settings);
  MapTiles.current = tiles;
  bool noTiles = false;
  final fixtures = {
    for (final mode in JourneyMode.values) mode: await _seed(dir, mode),
  };
  final look = ValueNotifier(Look.light);
  final mode = ValueNotifier(JourneyMode.road);
  final stressMode = ValueNotifier(false);
  final stress = await _seed(
    dir,
    JourneyMode.expedition,
    way: _stressWay,
    ground: _stressGround,
  );
  final history = ValueNotifier(false);
  final scale = ValueNotifier(1.0);
  final revision = ValueNotifier(0);
  await MapActivity.setNetworkEnabled(true);
  const MethodChannel('tripping/pause_probe').setMethodCallHandler((
    call,
  ) async {
    final fixture = stressMode.value ? stress : fixtures[mode.value]!;
    switch (call.method) {
      case 'light':
        look.value = Look.light;
      case 'dark':
        look.value = Look.dark;
      case 'sun':
        look.value = Look.highSun;
      case 'stress':
        stressMode.value = true;
        mode.value = JourneyMode.expedition;
        history.value = false;
        await stress.fix();
      case 'road':
        stressMode.value = false;
        mode.value = JourneyMode.road;
        history.value = false;
        await fixtures[mode.value]!.fix();
      case 'expedition':
        stressMode.value = false;
        mode.value = JourneyMode.expedition;
        history.value = false;
        await fixtures[mode.value]!.fix();
      case 'history':
        await fixture.recorder.end();
        history.value = true;
      case 'precise':
        fixture.approximate = false;
        await fixture.fix();
      case 'approximate':
        fixture.approximate = true;
        await fixture.fix();
      case 'pause':
        await fixture.recorder.pause();
        await MapActivity.setNetworkEnabled(false);
      case 'straight':
        await fixture.store.saveRoute(
          fixture.journey.id,
          kind: RouteKind.straight,
          provider: 'synthetic direction',
          computedAt: DateTime.now().toUtc(),
          meters: 300,
          geometry: encodePolyline([
            fixture.here,
            (fixture.route.latitude, fixture.route.longitude),
          ]),
        );
      case 'offline':
        noTiles = true;
        await MapActivity.setNetworkEnabled(false);
        // Inject an empty basemap only in this test package's style files.
        // Sources/layers used by the actual journey renderer remain intact.
        for (final appearance in Look.values) {
          final file = File(tiles.stylePath(appearance));
          final style =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
          style['sources'] = {
            'empty': {
              'type': 'geojson',
              'data': {'type': 'FeatureCollection', 'features': <Object>[]},
            },
          };
          style['layers'] = [
            layers.firstWhere((l) => l['type'] == 'background'),
            for (final id in [
              'water',
              'landcover_wood',
              'landuse_residential',
              'waterway',
              'highway_path',
              'highway_minor',
              'highway_major_inner',
              'highway_motorway_inner',
              'railway',
            ])
              {
                'id': id,
                'type': 'line',
                'source': 'empty',
                'paint': {'line-color': '#808080'},
              },
          ];
          await file.writeAsString(jsonEncode(style));
        }
        revision.value++;
      case 'online':
        await MapActivity.setNetworkEnabled(true);
      case 'largeText':
        scale.value = 2;
      case 'end':
        for (final f in [...fixtures.values, stress]) {
          await f.recorder.end();
        }
        await MapActivity.setNetworkEnabled(false);
      default:
        throw PlatformException(code: 'unknown-command');
    }
  });
  runApp(
    ListenableBuilder(
      listenable: Listenable.merge([
        look,
        mode,
        history,
        scale,
        revision,
        stressMode,
      ]),
      builder: (context, _) {
        final f = stressMode.value ? stress : fixtures[mode.value]!;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: trippingLook(look.value),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale.value)),
            child: child!,
          ),
          home: history.value
              ? Scaffold(
                  appBar: AppBar(title: const Text('Synthetic journey')),
                  body: FutureBuilder(
                    future: f.store.track(f.journey.id),
                    builder: (context, track) => FutureBuilder(
                      future: f.store.waypointsOf(f.journey.id),
                      builder: (context, points) => TrackMap(
                        track: track.data,
                        waypoints: points.data ?? [],
                        route: f.route,
                      ),
                    ),
                  ),
                )
              : RecordScreen(
                  key: ValueKey((mode.value, revision.value, stressMode.value)),
                  recorder: f.recorder,
                  location: f.location,
                  system: FakeSystemAccess(),
                  settings: settings,
                  waypoints: f.store,
                  planner: f.planner,
                  onMapNetworkChanged: (enabled) =>
                      MapActivity.setNetworkEnabled(enabled && !noTiles),
                  mapBuilder: (state, now) => JourneyMap(
                    state: state,
                    store: f.store,
                    now: now,
                    planner: f.planner,
                    identity: settings.identity.value,
                  ),
                ),
        );
      },
    ),
  );
}
