import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_style.dart';
import 'offline_area.dart';

/// A map for choosing an area: reports what it shows whenever it comes to
/// rest. Starts at [start] when there is one, else shows the world.
class AreaMap extends StatefulWidget {
  const AreaMap({super.key, required this.onArea, this.start});

  final ValueChanged<Area> onArea;
  final LatLng? start;

  @override
  State<AreaMap> createState() => _AreaMapState();
}

class _AreaMapState extends State<AreaMap> {
  MapLibreMapController? _map;

  Future<void> _report() async {
    final map = _map;
    if (map == null) return;
    final bounds = await map.getVisibleRegion();
    if (!mounted) return;
    widget.onArea((
      south: bounds.southwest.latitude,
      west: bounds.southwest.longitude,
      north: bounds.northeast.latitude,
      east: bounds.northeast.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    return MapLibreMap(
      styleString: mapStyleFor(context),
      initialCameraPosition: CameraPosition(
        target: start ?? const LatLng(20, 0),
        zoom: start == null ? 1 : 11,
      ),
      onMapCreated: (map) => _map = map,
      onStyleLoadedCallback: _report,
      onCameraIdle: _report,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomRight,
    );
  }
}
