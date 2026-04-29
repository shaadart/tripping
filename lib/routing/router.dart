import 'dart:async';
import 'dart:convert';

import '../journey/geo.dart';
import '../journey/journey.dart';
import '../net/http.dart';
import '../places/polyline.dart';

/// A way to a destination.
class PlannedRoute {
  const PlannedRoute({
    required this.kind,
    required this.provider,
    required this.computedAt,
    required this.meters,
    required this.points,
    this.seconds,
  });

  /// The straight line from [from] to [to]: what is known without a route.
  factory PlannedRoute.straight(
    (double, double) from,
    (double, double) to, {
    required DateTime at,
  }) => PlannedRoute(
    kind: RouteKind.straight,
    provider: 'straight line',
    computedAt: at,
    meters: metersBetween(from.$1, from.$2, to.$1, to.$2),
    points: [from, to],
  );

  final RouteKind kind;

  /// Where it came from, for honesty and support: "valhalla" or
  /// "straight line".
  final String provider;
  final DateTime computedAt;
  final double meters;

  /// The service's own travel time; null for a straight line.
  final double? seconds;

  /// Latitude and longitude along the way.
  final List<(double, double)> points;
}

/// Why no road route came back.
class RouteError implements Exception {
  const RouteError(this.message, {this.offline = false});

  final String message;
  final bool offline;

  @override
  String toString() => message;
}

/// Plans routes between two points.
abstract interface class RouteSource {
  Future<PlannedRoute> route(
    (double, double) from,
    (double, double) to,
    JourneyMode mode, {
    required DateTime at,
  });
}

/// Valhalla: open-source routing over OpenStreetMap (D-026). The FOSSGIS
/// instance allows at most one request a second and asks apps not to bake
/// its address in, so the address is a build setting and requests are
/// spaced.
abstract interface class CancellableRouteSource implements RouteSource {
  void cancelPending();
}

class ValhallaRouter implements CancellableRouteSource {
  ValhallaRouter({this.baseUrl = defaultUrl, Fetch? fetch}) : _fetch = fetch;

  static const defaultUrl = String.fromEnvironment(
    'TRIPPING_ROUTING_URL',
    defaultValue: 'https://valhalla1.openstreetmap.de',
  );

  static const _spacing = Duration(seconds: 1);
  static DateTime? _lastRequest;

  final String baseUrl;
  final Fetch? _fetch;
  var _cancellation = RequestCancellation();

  @override
  void cancelPending() {
    _cancellation.cancel();
    _cancellation = RequestCancellation();
  }

  @override
  Future<PlannedRoute> route(
    (double, double) from,
    (double, double) to,
    JourneyMode mode, {
    required DateTime at,
  }) async {
    final cancellation = _cancellation;
    cancellation.check();
    final last = _lastRequest;
    if (last != null) {
      final wait = _spacing - DateTime.now().difference(last);
      if (wait > Duration.zero) await cancellation.delay(wait);
    }
    _lastRequest = DateTime.now();
    final request = jsonEncode({
      'locations': [
        {'lat': from.$1, 'lon': from.$2},
        {'lat': to.$1, 'lon': to.$2},
      ],
      'costing': switch (mode) {
        JourneyMode.road => 'auto',
        JourneyMode.expedition => 'pedestrian',
      },
      'units': 'kilometers',
      'narrative': false,
    });
    final HttpAnswer answer;
    try {
      final uri = Uri.parse(
        '$baseUrl/route',
      ).replace(queryParameters: {'json': request});
      answer = await (_fetch == null
          ? httpGet(uri, cancellation: cancellation)
          : _fetch(uri));
      cancellation.check();
    } on NoConnection {
      throw const RouteError(
        'No road route without a connection.',
        offline: true,
      );
    }
    return routeFromValhalla(answer, at: at);
  }
}

/// A [PlannedRoute] from Valhalla's answer; a [RouteError] when it has
/// none.
PlannedRoute routeFromValhalla(HttpAnswer answer, {required DateTime at}) {
  Object? json;
  try {
    json = jsonDecode(answer.body);
  } on FormatException {
    json = null;
  }
  if (answer.status != 200) {
    final code = json is Map ? json['error_code'] : null;
    throw RouteError(switch (code) {
      // No path, unconnected regions, nothing routable near a point.
      442 || 170 || 171 => 'No road route found between here and there.',
      // Longer than this service will plan.
      154 => 'Too far for the route service to plan in one go.',
      _ =>
        'The route service is not answering (${answer.status}). Try again '
            'later.',
    });
  }
  final trip = json is Map ? json['trip'] : null;
  if (trip is! Map || trip['summary'] is! Map || trip['legs'] is! List) {
    throw const RouteError('The route service sent something unreadable.');
  }
  final summary = trip['summary'] as Map;
  final points = <(double, double)>[];
  for (final leg in (trip['legs'] as List).whereType<Map<Object?, Object?>>()) {
    final shape = leg['shape'];
    if (shape is! String) continue;
    final decoded = decodePolyline(shape);
    // Legs share their meeting point.
    points.addAll(points.isEmpty ? decoded : decoded.skip(1));
  }
  if (points.length < 2) {
    throw const RouteError('The route service sent an empty route.');
  }
  return PlannedRoute(
    kind: RouteKind.road,
    provider: 'valhalla',
    computedAt: at,
    meters: (summary['length'] as num).toDouble() * 1000,
    seconds: (summary['time'] as num?)?.toDouble(),
    points: points,
  );
}
