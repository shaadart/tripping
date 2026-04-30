import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../places/polyline.dart';
import 'map_style.dart';
import 'map_symbols.dart';
import 'map_key.dart';
import 'track_geometry.dart';

/// A past journey on the map: its track, one line per segment, with where it
/// began and ended, the way planned and the destination, framed to fit.
///
/// The map is created before the track has loaded, so its style loads at the
/// same time; a cover hides it until the track is drawn and framed.
class TrackMap extends StatefulWidget {
  const TrackMap({
    super.key,
    required this.track,
    this.waypoints = const [],
    this.route,
    this.onDrawn,
  });

  /// Null while it is still loading.
  final List<List<Fix>>? track;

  final List<WaypointRow> waypoints;

  /// Where the journey was going, if anywhere.
  final RouteRow? route;

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
    _drawing = false;
    _draw();
  }

  Future<void> _draw() async {
    final map = _map;
    final track = widget.track;
    if (!mounted || map == null || track == null || !_styleLoaded) return;
    if (_drawing) return;
    _drawing = true;
    await registerMapSymbols(map, context);
    if (!mounted) return;
    final route = widget.route;
    final geometry = route?.geometry;
    final way = geometry == null
        ? const <(double, double)>[]
        : decodePolyline(geometry);
    final kind = route?.kind;
    if (route != null && kind != null) {
      await map.addGeoJsonSource('route', routeFeatures(way, kind));
      if (!mounted) return;
      await addRouteLayers(map, context, 'route');
    }
    await map.addGeoJsonSource('track', trackFeatures(track));
    if (!mounted) return;
    await addRecordedLayers(map, context, ['track']);
    await map.addGeoJsonSource('ends', endsFeatures(track));
    if (!mounted) return;
    await addEndLayers(map, context, 'ends');
    await map.addGeoJsonSource('waypoints', waypointFeatures(widget.waypoints));
    if (!mounted) return;
    await addWaypointLayers(map, context, 'waypoints');
    if (route != null) {
      await map.addGeoJsonSource(
        'destination',
        destinationFeatures(route.destination, route.latitude, route.longitude),
      );
      if (!mounted) return;
      await addDestinationLayers(map, context, 'destination');
    }
    await fitCamera(
      map,
      track,
      also: [...way, if (route != null) (route.latitude, route.longitude)],
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
        const Positioned(top: 12, right: 12, child: MapKeyButton()),
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
