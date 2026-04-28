import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/theme.dart';
import '../journey/journey.dart';
import 'map_style.dart';
import 'track_geometry.dart';

/// A past journey on the map: its track, one line per segment, with where it
/// began and ended, framed to fit.
class TrackMap extends StatefulWidget {
  const TrackMap({super.key, required this.track});

  final List<List<Fix>> track;

  @override
  State<TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends State<TrackMap> {
  MapLibreMapController? _map;

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null || !mounted) return;
    final ember = Theme.of(context).colorScheme.primary.toHexStringRGB();
    await map.addGeoJsonSource('track', trackFeatures(widget.track));
    await map.addLineLayer('track', 'track-line', trackLine(ember));
    await map.addGeoJsonSource('ends', endsFeatures(widget.track));
    await map.addCircleLayer(
      'ends',
      'ends',
      CircleLayerProperties(
        circleRadius: 7,
        circleColor: [
          'match',
          ['get', 'end'],
          'start',
          Palette.moss.toHexStringRGB(),
          ember,
        ],
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2,
      ),
    );
    await fitCamera(
      map,
      widget.track,
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
    );
  }

  @override
  Widget build(BuildContext context) {
    final box = boundsOf(widget.track);
    return MapLibreMap(
      styleString: mapStyleFor(context),
      // Start over the track, not the whole world, so nothing flashes.
      initialCameraPosition: CameraPosition(
        target: box == null
            ? const LatLng(20, 0)
            : LatLng((box.south + box.north) / 2, (box.west + box.east) / 2),
        zoom: box == null ? 1 : 13,
      ),
      onMapCreated: (map) => _map = map,
      onStyleLoadedCallback: _onStyleLoaded,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomRight,
    );
  }
}
