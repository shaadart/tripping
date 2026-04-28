import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../journey/journey.dart';
import 'track_geometry.dart';

/// The bundled basemap style for the current theme. Bundled, so the map and
/// everything drawn on it work without the style server; only the tiles
/// need the network.
String mapStyleFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? 'assets/map/dark.json'
    : 'assets/map/positron.json';

/// How every recorded track is drawn.
LineLayerProperties trackLine(String color) => LineLayerProperties(
  lineColor: color,
  lineWidth: 5,
  lineCap: 'round',
  lineJoin: 'round',
);

/// Moves the camera to show all of [track]. A track smaller than a few
/// streets is shown at street level rather than zoomed in to fill the map.
Future<void> fitCamera(
  MapLibreMapController map,
  Iterable<List<Fix>> track, {
  EdgeInsets padding = const EdgeInsets.fromLTRB(48, 96, 48, 48),
}) async {
  final box = boundsOf(track);
  if (box == null) return;
  if (box.north - box.south < 0.002 && box.east - box.west < 0.002) {
    await map.moveCamera(
      CameraUpdate.newLatLngZoom(
        LatLng((box.south + box.north) / 2, (box.west + box.east) / 2),
        16,
      ),
    );
    return;
  }
  await map.moveCamera(
    CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(box.south, box.west),
        northeast: LatLng(box.north, box.east),
      ),
      left: padding.left,
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom,
    ),
  );
}
