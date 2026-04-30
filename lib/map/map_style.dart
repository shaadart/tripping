import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/theme.dart';
import '../app/identity_marker.dart';
import '../journey/journey.dart';
import 'map_tiles.dart';
import 'map_symbols.dart';
import 'track_geometry.dart';

/// The bundled basemap style for the current look. Bundled, so the map and
/// everything drawn on it work without the style server; only the tiles
/// need the network.
String mapStyleFor(BuildContext context) =>
    MapTiles.current?.stylePath(lookOf(context).look) ??
    lookOf(context).mapStyle;

/// How every recorded track is drawn in the current look.
LineLayerProperties trackLine(BuildContext context) => LineLayerProperties(
  lineColor: MapVisuals(context).recorded.toHexStringRGB(),
  lineWidth: lookOf(context).trackWidth,
  lineCap: 'round',
  lineJoin: 'round',
);

/// All casings go under all ink, so a recent tail cannot erase older ground
/// at a crossing. The route remains visible beside a coincident narrow track.
Future<void> addRecordedLayers(
  MapLibreMapController map,
  BuildContext context,
  List<String> sources,
) async {
  final visuals = MapVisuals(context);
  final ink = trackLine(context);
  for (final source in sources) {
    await map.addLineLayer(
      source,
      '$source-casing',
      LineLayerProperties(
        lineColor: visuals.ground.toHexStringRGB(),
        lineWidth: visuals.trackCasingWidth,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
  }
  for (final source in sources) {
    await map.addLineLayer(source, '$source-line', ink);
  }
}

/// The accuracy disc is ground context, below routes and every place marker.
Future<void> addAccuracyLayer(
  MapLibreMapController map,
  BuildContext context,
  String source,
) => map.addCircleLayer(
  source,
  'accuracy',
  CircleLayerProperties(
    circleRadius: groundRadius,
    circleColor: [
      'case',
      ['get', 'stale'],
      '#8A8378',
      MapVisuals(context).recorded.toHexStringRGB(),
    ],
    circleOpacity: 0.10,
    circleStrokeColor: [
      'case',
      ['get', 'stale'],
      '#8A8378',
      MapVisuals(context).recorded.toHexStringRGB(),
    ],
    circleStrokeWidth: 1,
    circleStrokeOpacity: 0.4,
    circlePitchAlignment: 'map',
  ),
);

/// Moves the camera to show all of [track]. A track smaller than a few
/// streets is shown at street level rather than zoomed in to fill the map.
Future<void> fitCamera(
  MapLibreMapController map,
  Iterable<List<Fix>> track, {
  Iterable<(double, double)> also = const [],
  EdgeInsets padding = const EdgeInsets.fromLTRB(48, 96, 48, 48),
}) async {
  final box = boundsOf(track, also: also);
  if (box == null) return;
  final centerLat = (box.south + box.north) / 2;
  final centerLon = (box.west + box.east) / 2;
  final south = box.north - box.south < .002 ? centerLat - .001 : box.south;
  final north = box.north - box.south < .002 ? centerLat + .001 : box.north;
  final west = box.east - box.west < .002 ? centerLon - .001 : box.west;
  final east = box.east - box.west < .002 ? centerLon + .001 : box.east;
  await map.moveCamera(
    CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(south, west),
        northeast: LatLng(north, east),
      ),
      left: padding.left,
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom,
    ),
  );
}

/// A broad directional corridor under the recorded line. Direction-only
/// geometry stays thin and dotted; it is never decorated as a traversable way.
Future<void> addRouteLayers(
  MapLibreMapController map,
  BuildContext context,
  String source,
) async {
  final v = MapVisuals(context);
  final iconScale = identityMapIconScale(context);
  final road = [
    '==',
    ['get', 'kind'],
    RouteKind.road.name,
  ];
  await map.addLineLayer(
    source,
    '$source-casing',
    LineLayerProperties(
      lineColor: v.ground.toHexStringRGB(),
      lineWidth: v.routeWidth + 2,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: road,
  );
  await map.addLineLayer(
    source,
    '$source-road',
    LineLayerProperties(
      lineColor: v.route.toHexStringRGB(),
      lineWidth: v.routeWidth,
      lineCap: 'round',
      lineJoin: 'round',
    ),
    filter: road,
  );
  await map.addSymbolLayer(
    source,
    '$source-direction',
    SymbolLayerProperties(
      symbolPlacement: 'line',
      symbolSpacing: 160,
      iconImage: MapSymbol.routeArrow.image,
      iconSize: iconScale,
      iconRotationAlignment: 'map',
      iconPitchAlignment: 'map',
      iconKeepUpright: false,
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    ),
    filter: road,
  );
  await map.addLineLayer(
    source,
    '$source-straight',
    LineLayerProperties(
      lineColor: v.route.toHexStringRGB(),
      lineWidth: 3,
      lineDasharray: [1, 2],
      lineCap: 'round',
    ),
    filter: [
      '==',
      ['get', 'kind'],
      RouteKind.straight.name,
    ],
  );
}

Future<void> addEndLayers(
  MapLibreMapController map,
  BuildContext context,
  String source,
) async {
  final iconScale = identityMapIconScale(context);
  for (final (end, symbol) in [
    ('start', MapSymbol.origin),
    ('finish', MapSymbol.finish),
  ]) {
    await map.addSymbolLayer(
      source,
      '$source-$end',
      SymbolLayerProperties(
        iconImage: symbol.image,
        iconSize: iconScale,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconPitchAlignment: 'viewport',
        iconRotationAlignment: 'viewport',
      ),
      filter: [
        '==',
        ['get', 'end'],
        end,
      ],
    );
  }
  if (!context.mounted) return;
  await _addPlaceLabel(map, context, source, '$source-labels', [
    'match',
    ['get', 'end'],
    'start',
    'Start',
    'Finish',
  ]);
}

/// The pin's tip anchors the destination; its body sits above a recorded
/// finish at the same coordinate, so intent and actual finish stay separate.
Future<void> addDestinationLayers(
  MapLibreMapController map,
  BuildContext context,
  String source,
) async {
  await map.addSymbolLayer(
    source,
    '$source-pin',
    SymbolLayerProperties(
      iconImage: MapSymbol.destination.image,
      iconSize: identityMapIconScale(context),
      iconAnchor: 'bottom',
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
      iconPitchAlignment: 'viewport',
      iconRotationAlignment: 'viewport',
    ),
  );
  if (!context.mounted) return;
  await _addPlaceLabel(map, context, source, '$source-label', ['get', 'name']);
}

Future<void> _addPlaceLabel(
  MapLibreMapController map,
  BuildContext context,
  String source,
  String layer,
  Object field, {
  double offset = 1.4,
}) async {
  final scheme = MapVisuals(context).scheme;
  await map.addSymbolLayer(
    source,
    layer,
    SymbolLayerProperties(
      textField: field,
      textFont: ['Noto Sans Regular'],
      textSize: lookOf(context).look == Look.highSun ? 14 : 13,
      textOffset: [0, offset],
      textAnchor: 'top',
      textColor: scheme.onSurface.toHexStringRGB(),
      textHaloColor: scheme.surface.toHexStringRGB(),
      textHaloWidth: 1.5,
      textOptional: true,
    ),
  );
}

/// Companions on [source] (see [companionFeatures]): moss and solid when
/// live, faded when aging, a hollow grey ring when stale; each named, with
/// its age once it is not live.
Future<void> addCompanionLayers(
  MapLibreMapController map,
  BuildContext context,
  String source,
) async {
  final scheme = MapVisuals(context).scheme;
  await map.addSymbolLayer(
    source,
    '$source-markers',
    SymbolLayerProperties(
      iconImage: ['get', 'marker'],
      iconSize: identityMapIconScale(context),
      iconOpacity: [
        'match',
        ['get', 'freshness'],
        'aging',
        0.55,
        1,
      ],
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
      iconPitchAlignment: 'viewport',
      iconRotationAlignment: 'viewport',
    ),
  );
  await map.addSymbolLayer(
    source,
    '$source-labels',
    SymbolLayerProperties(
      textField: ['get', 'label'],
      textFont: ['Noto Sans Regular'],
      textSize: 12,
      textOffset: [0, 2.0],
      textAnchor: 'top',
      textColor: scheme.onSurface.toHexStringRGB(),
      textHaloColor: scheme.surface.toHexStringRGB(),
      textHaloWidth: 1.5,
      textOptional: true,
    ),
  );
}

/// Diamonds distinguish waypoints from people, endpoints and the pin.
/// Filled = marked from a fix; open = a place chosen on the map.
Future<void> addWaypointLayers(
  MapLibreMapController map,
  BuildContext context,
  String source,
) async {
  await map.addSymbolLayer(
    source,
    '$source-markers',
    SymbolLayerProperties(
      iconImage: [
        'match',
        ['get', 'kind'],
        'marked',
        MapSymbol.marked.image,
        MapSymbol.planned.image,
      ],
      iconSize: identityMapIconScale(context),
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
      iconPitchAlignment: 'viewport',
      iconRotationAlignment: 'viewport',
    ),
  );
  if (!context.mounted) return;
  await _addPlaceLabel(map, context, source, '$source-labels', [
    'get',
    'label',
  ]);
}
