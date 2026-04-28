import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import 'map_style.dart';
import 'track_geometry.dart';

/// A past journey on the map: its track, one line per segment, with where it
/// began and ended, framed to fit.
///
/// The map is created before the track has loaded, so its style loads at the
/// same time; a cover hides it until the track is drawn and framed.
class TrackMap extends StatefulWidget {
  const TrackMap({
    super.key,
    required this.track,
    this.waypoints = const [],
    this.onDrawn,
  });

  /// Null while it is still loading.
  final List<List<Fix>>? track;

  final List<WaypointRow> waypoints;

  /// Called once the track is on the map, with the time since this widget
  /// was created.
  final void Function(Duration sinceCreated)? onDrawn;

  @override
  State<TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends State<TrackMap> {
  MapLibreMapController? _map;
  final _age = Stopwatch()..start();
  bool _styleLoaded = false;
  bool _drawing = false;
  bool _drawn = false;

  @override
  void didUpdateWidget(TrackMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _draw();
  }

  void _onStyleLoaded() {
    _styleLoaded = true;
    _draw();
  }

  Future<void> _draw() async {
    final map = _map;
    final track = widget.track;
    if (!mounted || map == null || track == null || !_styleLoaded) return;
    if (_drawing) return;
    _drawing = true;
    final ember = Theme.of(context).colorScheme.primary.toHexStringRGB();
    final line = trackLine(context);
    await map.addGeoJsonSource('track', trackFeatures(track));
    await map.addLineLayer('track', 'track-line', line);
    await map.addGeoJsonSource('ends', endsFeatures(track));
    await map.addCircleLayer(
      'ends',
      'ends',
      CircleLayerProperties(
        circleRadius: 7,
        // Start: white ringed in ember; finish: solid ember. Green is
        // kept for waypoints marked on the way.
        circleColor: [
          'match',
          ['get', 'end'],
          'start',
          '#FFFFFF',
          ember,
        ],
        circleStrokeColor: [
          'match',
          ['get', 'end'],
          'start',
          ember,
          '#FFFFFF',
        ],
        circleStrokeWidth: 3,
      ),
    );
    await map.addGeoJsonSource('waypoints', waypointFeatures(widget.waypoints));
    if (!mounted) return;
    await addWaypointLayers(map, context, 'waypoints');
    await fitCamera(
      map,
      track,
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
    );
    widget.onDrawn?.call(_age.elapsed);
    if (mounted) setState(() => _drawn = true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MapLibreMap(
          styleString: mapStyleFor(context),
          initialCameraPosition: const CameraPosition(
            target: LatLng(20, 0),
            zoom: 1,
          ),
          onMapCreated: (map) => _map = map,
          onStyleLoadedCallback: _onStyleLoaded,
          tiltGesturesEnabled: false,
          rotateGesturesEnabled: false,
          attributionButtonPosition: AttributionButtonPosition.bottomRight,
        ),
        if (!_drawn)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
