import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/theme.dart';
import '../journey/geo.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../recording/recorder.dart';
import '../recording/track_policy.dart';
import 'map_style.dart';
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
  });

  final RecorderState state;
  final JourneyStore store;
  final DateTime now;

  @override
  State<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<JourneyMap> {
  static const _historySource = 'track-history';
  static const _tailSource = 'track-tail';
  static const _positionSource = 'position';

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
    _serially(_sync);
  }

  /// Map calls are asynchronous; keep them in order.
  void _serially(Future<void> Function() task) {
    _queue = _queue.then((_) => mounted ? task() : null).catchError((_) {});
  }

  void _onStyleLoaded() {
    _serially(() async {
      final map = _map!;
      final ember = Theme.of(context).colorScheme.primary.toHexStringRGB();
      final line = trackLine(context);
      for (final source in [_historySource, _tailSource, _positionSource]) {
        await map.addGeoJsonSource(source, trackFeatures(const []));
      }
      for (final source in [_historySource, _tailSource]) {
        await map.addLineLayer(source, '$source-line', line);
      }
      await map.addCircleLayer(
        _positionSource,
        'accuracy',
        CircleLayerProperties(
          circleRadius: groundRadius,
          circleColor: ember,
          circleOpacity: 0.12,
          circleStrokeColor: ember,
          circleStrokeWidth: 1,
          circleStrokeOpacity: 0.35,
          circlePitchAlignment: 'map',
        ),
      );
      await map.addCircleLayer(
        _positionSource,
        'puck',
        CircleLayerProperties(
          circleRadius: 8,
          circleColor: [
            'case',
            ['get', 'hollow'],
            'rgba(0,0,0,0)',
            ember,
          ],
          circleStrokeColor: [
            'case',
            ['get', 'stale'],
            Palette.signal.toHexStringRGB(),
            '#FFFFFF',
          ],
          circleStrokeWidth: 3,
        ),
      );
      _styleReady = true;
      // The style can reload (theme change): redraw everything.
      _journeyId = null;
      await _sync();
    });
  }

  Future<void> _sync() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final state = widget.state;
    final (journey, progress) = switch (state) {
      Recording(:final journey, :final progress) ||
      Paused(:final journey, :final progress) ||
      Interrupted(:final journey, :final progress) => (journey, progress),
      Idle() => (null, null),
    };

    if (journey?.id != _journeyId) {
      _journeyId = journey?.id;
      _track.reset(
        journey == null ? const [] : await widget.store.track(journey.id),
      );
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
        await map.animateCamera(CameraUpdate.bearingTo(0));
        await map.animateCamera(CameraUpdate.tiltTo(0));
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

  Future<void> _drawTail(MapLibreMapController map) =>
      map.setGeoJsonSource(_tailSource, trackFeatures([_track.tail]));

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
      await map.animateCamera(_followView(fix));
      _zoomedIn = true;
    } else if (previous != null &&
        fix.metersTo(previous) < _easeAbove &&
        !turned) {
      // A step of a few pixels looks the same either way, and an ease
      // renders dozens of frames per fix on a 120 Hz screen (E-015).
      await map.moveCamera(_followUpdate(fix));
    } else {
      await map.animateCamera(_followUpdate(fix));
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

  /// Back to the journey's follow view.
  void _recenter() {
    setState(() => _follow = true);
    final fix = _shownFix;
    final map = _map;
    if (fix == null || map == null) return;
    _serially(() async => map.animateCamera(_followView(fix)));
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
            onMapCreated: (map) => _map = map,
            onStyleLoadedCallback: _onStyleLoaded,
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
            bottom: 16,
            child: Center(child: _MapNote('Map not available here')),
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
