import 'package:flutter/foundation.dart';

import '../journey/journey.dart';
import '../net/http.dart';
import '../journey/journey_store.dart';
import '../places/place.dart';
import '../places/polyline.dart';
import 'router.dart';

/// The name of a destination picked on the map rather than found by name.
const mapPoint = 'Point on the map';

/// Destinations and the way there, kept with each journey (E2).
///
/// Without a road route (no connection, nothing found) the way is a straight
/// line, stored and shown as one, never as a road.
class RoutePlanner {
  RoutePlanner(this._store, this._router, {this.clock = _utcNow});

  static DateTime _utcNow() => DateTime.now().toUtc();

  final JourneyStore _store;
  final RouteSource _router;
  int _generation = 0;

  /// Stops HTTP and rate-limit timers; late answers cannot change the plan.
  void cancelPending() {
    _generation++;
    final router = _router;
    if (router is CancellableRouteSource) router.cancelPending();
  }

  final DateTime Function() clock;

  /// Where the next journey will go, chosen before it starts.
  final pending = ValueNotifier<Place?>(null);

  Stream<RouteRow?> watch(int journeyId) => _store.watchRoute(journeyId);

  /// Sends [journeyId] to [place]. The way there is planned separately,
  /// once there is a position to start from (see [plan]). A searched place
  /// is remembered for next time unless [remember] is false (a waypoint of
  /// this journey, say).
  Future<void> goTo(int journeyId, Place place, {bool remember = true}) async {
    await _store.setDestination(
      journeyId,
      name: place.name,
      detail: place.detail,
      latitude: place.latitude,
      longitude: place.longitude,
    );
    if (remember && place.name != mapPoint) {
      await _store.rememberPlace(
        name: place.name,
        detail: place.detail,
        latitude: place.latitude,
        longitude: place.longitude,
        at: clock(),
      );
    }
  }

  /// Plans the way from [from] to the journey's destination: by road when
  /// the service answers, else a straight line. Returns why the way is a
  /// straight line, when it is; null when it is a road, or there is no
  /// destination.
  ///
  /// With [keepOnFailure] (a new way after leaving the road), a failure
  /// keeps the way there is: an old road beats a new straight line.
  Future<RouteError?> plan(
    int journeyId,
    (double, double) from,
    JourneyMode mode, {
    bool keepOnFailure = false,
  }) async {
    final generation = _generation;
    final destination = await _store.routeOf(journeyId);
    if (destination == null || generation != _generation) return null;
    final to = (destination.latitude, destination.longitude);
    PlannedRoute route;
    RouteError? why;
    try {
      route = await _router.route(from, to, mode, at: clock());
    } on RequestCancelled {
      return null;
    } on RouteError catch (error) {
      if (keepOnFailure) return error;
      why = error;
      route = PlannedRoute.straight(from, to, at: clock());
    }
    // The destination may have changed while the service was answering: a
    // way to the old one must not be kept for the new one.
    final now = await _store.routeOf(journeyId);
    if (generation != _generation ||
        now == null ||
        (now.latitude, now.longitude) != to) {
      return why;
    }
    await _store.saveRoute(
      journeyId,
      kind: route.kind,
      provider: route.provider,
      computedAt: route.computedAt,
      meters: route.meters,
      seconds: route.seconds,
      geometry: encodePolyline(route.points),
    );
    return why;
  }

  Future<void> clear(int journeyId) {
    cancelPending();
    return _store.clearDestination(journeyId);
  }

  /// Places chosen before, newest first.
  Future<List<Place>> recent() async => [
    for (final place in await _store.latestPlaces())
      Place(
        name: place.name,
        detail: place.detail,
        latitude: place.latitude,
        longitude: place.longitude,
      ),
  ];
}
