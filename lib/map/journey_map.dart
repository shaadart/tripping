import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/theme.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../recording/recorder.dart';
import '../recording/track_policy.dart';
import 'track_geometry.dart';

/// Seconds without a fix after which the position is drawn as stale.
const _staleAfter = Duration(seconds: 15);

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
      for (final source in [_historySource, _tailSource, _positionSource]) {
        await map.addGeoJsonSource(source, trackFeatures(const []));
      }
      for (final source in [_historySource, _tailSource]) {
        await map.addLineLayer(
          source,
          '$source-line',
          LineLayerProperties(
            lineColor: ember,
            lineWidth: 5,
            lineCap: 'round',
            lineJoin: 'round',
          ),
        );
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
      await _drawHistory(map);
      await _drawTail(map);
      await _fitTrack(map);
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
    _shownFix = fix;
    if (state is! Recording || !_follow) return;
    final target = LatLng(fix.latitude, fix.longitude);
    await map.animateCamera(
      _zoomedIn
          ? CameraUpdate.newLatLng(target)
          : CameraUpdate.newLatLngZoom(target, 16),
    );
    _zoomedIn = true;
  }

  Future<void> _fitTrack(MapLibreMapController map) async {
    final fixes = [for (final segment in _track.segments) ...segment];
    if (fixes.isEmpty) return;
    var south = fixes.first.latitude, north = south;
    var west = fixes.first.longitude, east = west;
    for (final fix in fixes) {
      if (fix.latitude < south) south = fix.latitude;
      if (fix.latitude > north) north = fix.latitude;
      if (fix.longitude < west) west = fix.longitude;
      if (fix.longitude > east) east = fix.longitude;
    }
    if (north - south < 0.002 && east - west < 0.002) {
      await map.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng((south + north) / 2, (west + east) / 2),
          16,
        ),
      );
    } else {
      await map.moveCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(south, west),
            northeast: LatLng(north, east),
          ),
          left: 48,
          top: 96,
          right: 48,
          bottom: 48,
        ),
      );
    }
    _zoomedIn = true;
  }

  void _recenter() {
    setState(() => _follow = true);
    final fix = _shownFix;
    final map = _map;
    if (fix == null || map == null) return;
    _serially(
      () async => map.animateCamera(
        CameraUpdate.newLatLng(LatLng(fix.latitude, fix.longitude)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
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
            styleString: dark
                ? 'assets/map/dark.json'
                : 'assets/map/positron.json',
            initialCameraPosition: const CameraPosition(
              target: LatLng(20, 0),
              zoom: 1,
            ),
            onMapCreated: (map) => _map = map,
            onStyleLoadedCallback: _onStyleLoaded,
            tiltGesturesEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
          ),
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
