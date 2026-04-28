import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/theme.dart';
import '../journey/journey.dart';
import 'map_tiles.dart';
import 'track_geometry.dart';

/// The bundled basemap style for the current look. Bundled, so the map and
/// everything drawn on it work without the style server; only the tiles
/// need the network.
String mapStyleFor(BuildContext context) =>
    MapTiles.current?.stylePath(lookOf(context).look) ??
    lookOf(context).mapStyle;

/// How every recorded track is drawn in the current look.
LineLayerProperties trackLine(BuildContext context) => LineLayerProperties(
  lineColor: Theme.of(context).colorScheme.primary.toHexStringRGB(),
  lineWidth: lookOf(context).trackWidth,
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

/// Waypoints on [source]: a solid moss dot where you were, a hollow river
/// ring where you plan to go (nobody has been there), each with its label.
Future<void> addWaypointLayers(
  MapLibreMapController map,
  BuildContext context,
  String source,
) async {
  final scheme = Theme.of(context).colorScheme;
  final marked = scheme.tertiary.toHexStringRGB();
  final planned = scheme.secondary.toHexStringRGB();
  final ink = scheme.onSurface.toHexStringRGB();
  final halo = scheme.surface.toHexStringRGB();
  await map.addCircleLayer(
    source,
    '$source-dots',
    CircleLayerProperties(
      circleRadius: 7,
      circleColor: [
        'match',
        ['get', 'kind'],
        'marked',
        marked,
        'rgba(0,0,0,0)',
      ],
      circleStrokeColor: [
        'match',
        ['get', 'kind'],
        'marked',
        '#FFFFFF',
        planned,
      ],
      circleStrokeWidth: 3,
    ),
  );
  await map.addSymbolLayer(
    source,
    '$source-labels',
    SymbolLayerProperties(
      textField: ['get', 'label'],
      textFont: ['Noto Sans Regular'],
      textSize: 13,
      textOffset: [0, 1.2],
      textAnchor: 'top',
      textColor: ink,
      textHaloColor: halo,
      textHaloWidth: 1.5,
      textOptional: true,
    ),
  );
}
