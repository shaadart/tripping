import 'dart:async';
import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/theme.dart';
import '../app/identity_marker.dart';
import '../group/identity.dart';
import '../group/group_sync.dart';
import '../journey/geo.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../recording/recorder.dart';
import '../recording/track_policy.dart';
import '../app/waypoint_sheet.dart';
import '../places/place.dart';
import '../places/polyline.dart';
import '../routing/route_planner.dart';
import 'map_style.dart';
import 'map_symbols.dart';
import 'map_key.dart';
import 'terrain.dart';
import 'track_geometry.dart';

/// Seconds without a fix after which the position is drawn as stale.
const _staleAfter = Duration(seconds: 15);

/// Basemap layers (in both bundled styles) that draw something almost
/// anywhere. When none of them has a feature on screen, the map has nothing
/// to show there: offline in a place never viewed, or no map data.
const _basemapLayers = [
  'water',
  'landcover_wood',
  'landuse_residential',
  'waterway',
  'highway_path',
  'highway_minor',
  'highway_major_inner',
  'highway_motorway_inner',
  'railway',
];

/// Steps longer than this (driving speeds, at one fix a second) ease the
/// camera; shorter ones move it at once.
const _easeAbove = 15.0;

/// Speed in m/s above which the GPS heading is trusted to turn the road
/// camera.
const _headingAbove = 2.0;

/// Metres moved, well beyond GPS noise, before a course is taken from the
/// positions themselves when the GPS gives no heading.
const _courseAfter = 25.0;

/// How often, at most, to check whether the basemap is blank.
const _blankCheckEvery = Duration(seconds: 10);

/// The map under a journey: basemap, the recorded track and the position.
///
/// Reads from the store and the recorder state; never writes. The style is
/// bundled, so the track and position draw even when no tiles load.
class JourneyMap extends StatefulWidget {
  const JourneyMap({
    super.key,
    required this.state,
    required this.store,
    required this.now,
    this.planner,
    this.group,
    this.identity = const MapIdentity(),
  });

  final MapIdentity identity;
  final RecorderState state;
  final JourneyStore store;
  final DateTime now;

  /// Destinations and routes to draw; also lets a long press choose one.
  final RoutePlanner? planner;

  /// Companions to draw, with how fresh their positions are (G3).
  final ValueListenable<GroupStatus?>? group;

  @override
  State<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<JourneyMap> with WidgetsBindingObserver {
  static const _historySource = 'track-history';
  static const _tailSource = 'track-tail';
  static const _positionSource = 'position';
  static const _endSource = 'journey-ends';
  Fix? _originDrawn;
  static const _waypointSource = 'waypoints';
  static const _routeSource = 'route';
  static const _destinationSource = 'destination';
  static const _companionSource = 'companions';

  /// The companions last drawn, to skip redrawing what has not changed.
  String? _companionsDrawn;
  final _markerImages = <String>{};

  MapLibreMapController? _map;
  bool _styleReady = false;
  Future<void> _queue = Future.value();

  final _track = TrackBuffer();
  int? _journeyId;
  DateTime? _segmentStart;
  Fix? _shownFix;
  bool _follow = true;
  bool _zoomedIn = false;
  Offset? _touchStart;
  bool _blank = false;
  StreamSubscription<List<WaypointRow>>? _waypointWatch;

  /// The journey's waypoints as drawn, to answer a tap on one.
  List<WaypointRow> _waypoints = const [];
  Timer? _blankTimer;
  bool _visible = true;
  bool get _polling =>
      _visible && widget.state is! Paused && widget.state is! Interrupted;

  void _syncPolling() {
    if (!_polling) {
      _blankTimer?.cancel();
      _blankTimer = null;
    } else if (_styleReady) {
      _blankTimer ??= Timer.periodic(_blankCheckEvery, (_) {
        final map = _map;
        if (map != null) _serially(() => _checkBlank(map));
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _syncPolling();
    if (_visible) {
      // Rebuild the full saved track after background recording; never
      // draw a shortcut from the former tail to only the newest fix.
      _journeyId = null;
      _serially(_sync);
    }
  }

  StreamSubscription<RouteRow?>? _routeWatch;
  JourneyMode _mode = JourneyMode.expedition;

  /// The road camera's heading, kept while the GPS heading is unreliable.
  double _bearing = 0;

  /// Where the course without a GPS heading is measured from.
  Fix? _courseFrom;
  DateTime? _blankCheckedAt;
  int _blankChecks = 0;

  @override
  void didUpdateWidget(JourneyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPolling();
    _serially(_sync);
  }

  /// Map calls are asynchronous; keep them in order.
  void _serially(Future<void> Function() task) {
    _queue = _queue.then((_) => mounted ? task() : null).catchError((_) {});
  }

  void _onStyleLoaded() {
    _serially(() async {
      final map = _map!;
      final iconScale = identityMapIconScale(context);
      _markerImages.clear();
      await registerMapSymbols(map, context);
      if (!mounted) return;
      await map.addGeoJsonSource(_positionSource, trackFeatures(const []));
      if (!mounted) return;
      await addAccuracyLayer(map, context, _positionSource);
      // The planned way first, so the track drawn on top shows where the
      // journey really went.
      await map.addGeoJsonSource(_routeSource, trackFeatures(const []));
      if (!mounted) return;
      await addRouteLayers(map, context, _routeSource);
      for (final source in [_historySource, _tailSource]) {
        await map.addGeoJsonSource(source, trackFeatures(const []));
      }
      if (!mounted) return;
      await addRecordedLayers(map, context, [_historySource, _tailSource]);
      await map.addGeoJsonSource(_endSource, endsFeatures(const []));
      if (!mounted) return;
      await addEndLayers(map, context, _endSource);
      _originDrawn = null;
      // Waypoints above the track, below the position.
      await map.addGeoJsonSource(_waypointSource, waypointFeatures(const []));
      if (!mounted) return;
      await addWaypointLayers(map, context, _waypointSource);
      await map.addGeoJsonSource(_destinationSource, trackFeatures(const []));
      if (!mounted) return;
      await addDestinationLayers(map, context, _destinationSource);
      await map.addGeoJsonSource(_companionSource, trackFeatures(const []));
      if (!mounted) return;
      await addCompanionLayers(map, context, _companionSource);
      _companionsDrawn = null;
      await map.addSymbolLayer(
        _positionSource,
        'puck',
        SymbolLayerProperties(
          iconImage: ['get', 'marker'],
          iconSize: iconScale,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconPitchAlignment: 'viewport',
          iconRotationAlignment: 'viewport',
        ),
      );
      _styleReady = true;
      // Checked on its own clock too: with no journey there are no updates,
      // and a check made while the style was still loading must not stick.
      _syncPolling();
      // The style can reload (theme change): redraw everything.
      _journeyId = null;
      await _sync();
    });
  }

  Future<void> _sync() async {
    final map = _map;
    if (!_visible || map == null || !_styleReady) return;
    await _ensureMarker(map, widget.identity);
    await _drawCompanions(map);
    final state = widget.state;
    final (journey, progress) = switch (state) {
      Recording(:final journey, :final progress) ||
      Paused(:final journey, :final progress) ||
      Interrupted(:final journey, :final progress) => (journey, progress),
      Idle() => (null, null),
    };

    if (journey?.id != _journeyId) {
      _journeyId = journey?.id;
      await _shade(map, journey?.mode);
      _watchWaypoints(map, journey?.id);
      _watchRoute(map, journey?.id);
      _track.reset(
        journey == null ? const [] : await widget.store.track(journey.id),
      );
      _originDrawn = null;
      _segmentStart = progress?.openSince;
      _follow = true;
      _zoomedIn = false;
      _bearing = 0;
      _courseFrom = null;
      await _drawHistory(map);
      await _drawTail(map);
      await _fitTrack(map);
      if (journey == null) {
        // Between journeys it is a plain map again: north up and flat.
        await _moveCamera(map, CameraUpdate.bearingTo(0));
        await _moveCamera(map, CameraUpdate.tiltTo(0));
      }
    }

    if (state is Recording) {
      if (state.progress.openSince != _segmentStart) {
        _segmentStart = state.progress.openSince;
        _track.startSegment();
        await _drawHistory(map);
      }
      final stored = state.progress.lastFix;
      final last = _track.lastFix;
      if (stored != null && (last == null || stored.time.isAfter(last.time))) {
        _track.add(stored);
        if (_track.tailIsLong) {
          _track.foldTail();
          await _drawHistory(map);
        }
        await _drawTail(map);
      }
    }

    await _drawPosition(map, state);
    await _checkBlank(map);
  }

  Future<void> _drawHistory(MapLibreMapController map) =>
      map.setGeoJsonSource(_historySource, trackFeatures(_track.history));

  Future<void> _drawTail(MapLibreMapController map) async {
    await map.setGeoJsonSource(_tailSource, trackFeatures([_track.tail]));
    final first = _track.segments.where((s) => s.isNotEmpty).firstOrNull?.first;
    if (first == null || first != _originDrawn) {
      _originDrawn = first;
      await map.setGeoJsonSource(
        _endSource,
        endsFeatures(_track.segments, includeFinish: false),
      );
    }
  }

  Future<void> _drawPosition(
    MapLibreMapController map,
    RecorderState state,
  ) async {
    // While recording, the device's newest fix (even one too inaccurate for
    // the track); otherwise the last stored fix, which is no longer live.
    final (fix, stale) = switch (state) {
      Recording(:final latestFix?, :final latestFixArrivedAt?) => (
        latestFix,
        widget.now.difference(latestFixArrivedAt) > _staleAfter,
      ),
      Recording(:final progress) ||
      Paused(:final progress) ||
      Interrupted(:final progress) => (progress.lastFix, true),
      Idle() => (null, true),
    };
    final mode = switch (state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey.mode,
      Idle() => JourneyMode.expedition,
    };
    await map.setGeoJsonSource(
      _positionSource,
      positionFeatures(
        fix,
        stale: stale,
        maxAccuracy: TrackPolicy.of(mode).maxAccuracy,
        identity: widget.identity,
      ),
    );
    if (fix == null || identical(fix, _shownFix)) return;
    final previous = _shownFix;
    _shownFix = fix;
    _mode = mode;
    if (state is! Recording || !_follow) return;
    final bearing = _bearing;
    // On the road the map turns with the direction of travel: the heading
    // the GPS measured at real speed (standing still, it would spin), or,
    // without one, the way the last 25 m went.
    if (mode == JourneyMode.road) {
      final anchor = _courseFrom;
      if ((fix.speed ?? 0) >= _headingAbove && fix.heading != null) {
        _bearing = fix.heading!;
        _courseFrom = fix;
      } else if (anchor == null) {
        _courseFrom = fix;
      } else if (fix.heading == null && anchor.metersTo(fix) >= _courseAfter) {
        _bearing = anchor.bearingTo(fix);
        _courseFrom = fix;
      }
    }
    final turned = _turn(bearing, _bearing) > 10;
    if (!_zoomedIn) {
      await _moveCamera(map, _followView(fix));
      _zoomedIn = true;
    } else if (previous != null &&
        fix.metersTo(previous) < _easeAbove &&
        !turned) {
      // A step of a few pixels looks the same either way, and an ease
      // renders dozens of frames per fix on a 120 Hz screen (E-015).
      await map.moveCamera(_followUpdate(fix));
    } else {
      await _moveCamera(map, _followUpdate(fix));
    }
  }

  /// The follow view of the journey's kind, at street level: north up for
  /// an expedition, heading up and tilted on the road.
  CameraUpdate _followView(Fix fix) => CameraUpdate.newCameraPosition(
    CameraPosition(
      target: LatLng(fix.latitude, fix.longitude),
      zoom: 16,
      bearing: _mode == JourneyMode.road ? _bearing : 0,
      tilt: _mode == JourneyMode.road ? 45 : 0,
    ),
  );

  /// Keeps an expedition's zoom (a double tap does not stop following); on
  /// the road the whole view follows.
  CameraUpdate _followUpdate(Fix fix) => _mode == JourneyMode.road
      ? _followView(fix)
      : CameraUpdate.newLatLng(LatLng(fix.latitude, fix.longitude));

  /// Degrees between two headings, either way round.
  static double _turn(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  Future<void> _fitTrack(MapLibreMapController map) async {
    if (_track.lastFix == null) return;
    await fitCamera(map, _track.segments);
    _zoomedIn = true;
  }

  /// Asks MapLibre whether any basemap feature is drawn on screen. Runs with
  /// the regular updates rather than on "map idle": offline, failed tiles
  /// keep retrying and the map never becomes idle.
  Future<void> _checkBlank(MapLibreMapController map) async {
    if (!_polling) return;
    final now = DateTime.now();
    final last = _blankCheckedAt;
    if (last != null && now.difference(last) < _blankCheckEvery) return;
    _blankCheckedAt = now;
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // MapLibre queries in physical pixels.
    final size = box.size * MediaQuery.devicePixelRatioOf(context);
    final features = await map.queryRenderedFeaturesInRect(
      Offset.zero & size,
      _basemapLayers,
      null,
    );
    _blankChecks = features.isEmpty ? _blankChecks + 1 : 0;
    // Tiles take a few seconds to arrive after a move, so only a map still
    // blank at the next check is called unavailable.
    final blank = _blankChecks >= 2;
    if (mounted && blank != _blank) setState(() => _blank = blank);
  }

  /// Keeps the waypoint layer in step with the store for [journeyId].
  /// Companions where they last were, solid when live and hollow grey
  /// when stale; redrawn only when something changed (ages move each
  /// second, but a label only each minute).
  Future<void> _drawCompanions(MapLibreMapController map) async {
    final status = widget.group?.value;
    for (final companion in status?.companions ?? <Companion>[]) {
      await _ensureMarker(map, companion.shared.identity);
    }
    final features = companionFeatures(
      status == null || status.ended ? const [] : status.companions,
      widget.now,
      forceStale: status?.suspended == true,
    );
    final drawn = jsonEncode(features);
    if (drawn == _companionsDrawn) return;
    _companionsDrawn = drawn;
    await map.setGeoJsonSource(_companionSource, features);
  }

  Future<void> _ensureMarker(
    MapLibreMapController map,
    MapIdentity identity,
  ) async {
    for (final hollow in [false, true]) {
      final key = identityMarkerKey(identity, hollow: hollow);
      if (_markerImages.contains(key)) continue;
      final bytes = await identityMarkerPng(identity, hollow: hollow);
      if (!mounted) return;
      await map.addImage(key, bytes);
      _markerImages.add(key);
    }
  }

  /// Terrain-forward on an expedition, quieter on the road (D2).
  Future<void> _shade(MapLibreMapController map, JourneyMode? mode) async {
    final strength = terrainShading(lookOf(context).look.name, mode);
    try {
      await map.setLayerProperties(
        'hillshade',
        HillshadeLayerProperties(hillshadeExaggeration: strength),
      );
    } on Object {
      // A style without hill shading: nothing to adjust.
    }
  }

  void _watchWaypoints(MapLibreMapController map, int? journeyId) {
    _waypointWatch?.cancel();
    _waypointWatch = null;
    _waypoints = const [];
    if (journeyId == null) {
      _serially(
        () => map.setGeoJsonSource(_waypointSource, waypointFeatures(const [])),
      );
      return;
    }
    _waypointWatch = widget.store.watchWaypoints(journeyId).listen((waypoints) {
      _waypoints = waypoints;
      _serially(
        () =>
            map.setGeoJsonSource(_waypointSource, waypointFeatures(waypoints)),
      );
    });
  }

  /// Draws the journey's destination and the way there; with no journey,
  /// the destination chosen for the next one.
  void _watchRoute(MapLibreMapController map, int? journeyId) {
    _routeWatch?.cancel();
    _routeWatch = null;
    widget.planner?.pending.removeListener(_drawPending);
    final planner = widget.planner;
    if (planner == null) return;
    if (journeyId == null) {
      planner.pending.addListener(_drawPending);
      _drawPending();
      return;
    }
    _routeWatch = planner.watch(journeyId).listen((route) {
      _serially(() async {
        await map.setGeoJsonSource(
          _routeSource,
          route?.kind == null || route?.geometry == null
              ? trackFeatures(const [])
              : routeFeatures(decodePolyline(route!.geometry!), route.kind!),
        );
        await map.setGeoJsonSource(
          _destinationSource,
          route == null
              ? trackFeatures(const [])
              : destinationFeatures(
                  route.destination,
                  route.latitude,
                  route.longitude,
                ),
        );
      });
    });
  }

  void _drawPending() {
    final map = _map;
    final pending = widget.planner?.pending.value;
    if (map == null) return;
    _serially(() async {
      await map.setGeoJsonSource(_routeSource, trackFeatures(const []));
      await map.setGeoJsonSource(
        _destinationSource,
        pending == null
            ? trackFeatures(const [])
            : destinationFeatures(
                pending.name,
                pending.latitude,
                pending.longitude,
              ),
      );
    });
  }

  /// A long press offers to go there, or, on a journey, to plan a point
  /// there; without destinations it plans the point at once.
  Future<void> _longPress(LatLng at) async {
    final planner = widget.planner;
    if (planner == null) return _plan(at);
    final journey = switch (widget.state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey,
      Idle() => null,
    };
    final goHere = ListTile(
      leading: const Icon(Icons.flag_circle_outlined),
      title: const Text('Go here'),
      subtitle: Text(
        journey == null
            ? 'Make it the destination of the next journey'
            : 'Make it the destination of this journey',
      ),
      onTap: () => Navigator.pop(context, 'go'),
    );
    final planHere = ListTile(
      leading: const Icon(Icons.outlined_flag),
      title: const Text('Plan a point here'),
      subtitle: const Text('A waypoint you mean to reach'),
      onTap: () => Navigator.pop(context, 'plan'),
    );
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // Waypoints first on an expedition (D2).
          children: switch (journey?.mode) {
            null => [goHere],
            JourneyMode.road => [goHere, planHere],
            JourneyMode.expedition => [planHere, goHere],
          },
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'go':
        final place = Place(
          name: mapPoint,
          latitude: at.latitude,
          longitude: at.longitude,
        );
        if (journey == null) {
          planner.pending.value = place;
        } else {
          await planner.goTo(journey.id, place);
        }
      case 'plan':
        await _plan(at);
    }
  }

  /// A tapped waypoint can become where the journey is heading.
  Future<void> _waypointTapped(String id, String layerId) async {
    final planner = widget.planner;
    final journey = switch (widget.state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey,
      Idle() => null,
    };
    if (planner == null || journey == null) return;
    if (!layerId.startsWith(_waypointSource)) return;
    final index = _waypoints.indexWhere((w) => '${w.id}' == id);
    if (index < 0) return;
    final waypoint = _waypoints[index];
    final name = waypoint.name ?? 'Waypoint ${waypointLabel(waypoint, index)}';
    final head = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.near_me_outlined),
          title: Text('Head to $name'),
          subtitle: const Text(
            'Make it the destination: its distance and direction show below',
          ),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (!(head ?? false) || !mounted) return;
    await planner.goTo(
      journey.id,
      Place(
        name: name,
        latitude: waypoint.latitude,
        longitude: waypoint.longitude,
      ),
      remember: false,
    );
  }

  /// A long press plans a point there, on the journey under way.
  Future<void> _plan(LatLng at) async {
    final journey = switch (widget.state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey,
      Idle() => null,
    };
    if (journey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start a journey to plan points on it')),
      );
      return;
    }
    final waypoint = await widget.store.addWaypoint(
      journey.id,
      kind: WaypointKind.planned,
      at: widget.now,
      latitude: at.latitude,
      longitude: at.longitude,
    );
    if (!mounted) return;
    await showWaypointSheet(context, store: widget.store, waypoint: waypoint);
  }

  @override
  void initState() {
    super.initState();
    _visible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.group?.addListener(_groupChanged);
  }

  void _groupChanged() {
    final map = _map;
    if (map != null && _styleReady) _serially(() => _drawCompanions(map));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.group?.removeListener(_groupChanged);
    _routeWatch?.cancel();
    widget.planner?.pending.removeListener(_drawPending);
    _blankTimer?.cancel();
    _waypointWatch?.cancel();
    super.dispose();
  }

  Future<void> _moveCamera(
    MapLibreMapController map,
    CameraUpdate update,
  ) async {
    if (MediaQuery.disableAnimationsOf(context)) {
      await map.moveCamera(update);
    } else {
      await map.animateCamera(
        update,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  /// Back to the journey's follow view.
  void _recenter() {
    setState(() => _follow = true);
    final fix = _shownFix;
    final map = _map;
    if (fix == null || map == null) return;
    _serially(() async => _moveCamera(map, _followView(fix)));
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.state is Recording;
    return Stack(
      children: [
        // A drag on the map means the user wants to look around: stop
        // following until they ask to recenter.
        Listener(
          onPointerDown: (event) => _touchStart = event.position,
          onPointerMove: (event) {
            final start = _touchStart;
            if (_follow &&
                start != null &&
                (event.position - start).distance > 12) {
              setState(() => _follow = false);
            }
          },
          child: MapLibreMap(
            styleString: mapStyleFor(context),
            initialCameraPosition: const CameraPosition(
              target: LatLng(20, 0),
              zoom: 1,
            ),
            onMapCreated: (map) {
              _map = map;
              map.onFeatureTapped.add(
                (_, _, id, layerId, _) =>
                    unawaited(_waypointTapped(id, layerId)),
              );
            },
            onStyleLoadedCallback: _onStyleLoaded,
            onMapLongClick: (_, at) => _longPress(at),
            // Below the status bar, level with the header (the road view
            // turns, so the compass shows where north is).
            compassViewPosition: CompassViewPosition.topRight,
            compassViewMargins: Point(
              16,
              MediaQuery.paddingOf(context).top + 12,
            ),
            tiltGesturesEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
          ),
        ),
        if (_blank)
          Positioned(
            left: 16,
            right: 16,
            // Under the header, clear of the buttons at the bottom.
            top: MediaQuery.paddingOf(context).top + 64,
            child: Center(
              child: _MapNote(
                _track.lastFix == null
                    ? 'Map not available here'
                    : 'Map unavailable · saved journey still shown',
              ),
            ),
          ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 124,
          right: 16,
          child: const MapKeyButton(),
        ),
        if (recording && !_follow && _shownFix != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              onPressed: _recenter,
              tooltip: 'Follow my position',
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }
}

class _MapNote extends StatelessWidget {
  const _MapNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
