import 'dart:math';

import '../journey/geo.dart';
import '../journey/journey.dart';

/// How far along a planned way the phone is, as of one fix.
class RouteProgress {
  const RouteProgress({
    required this.metersLeft,
    this.secondsLeft,
    this.offRoute = false,
    this.arrived = false,
  });

  /// Along the road while on it; in a straight line for a straight way or
  /// once off the road.
  final double metersLeft;

  /// The service's estimate for what is left; null without one (a straight
  /// line, or off the road).
  final double? secondsLeft;

  /// Away from the road for long enough that it is not GPS noise.
  final bool offRoute;
  final bool arrived;
}

/// Follows fixes along one planned way (E3): projects each onto the road,
/// says what is left, and notices leaving the road or arriving.
///
/// Pure Dart; geometry in metres on a local flat plane around each fix,
/// which is far finer than GPS error over a road segment.
class RouteFollower {
  RouteFollower({
    required List<(double, double)> points,
    required this.kind,
    required this.meters,
    required this.seconds,
    required this.destination,
  }) : _points = points,
       _along = _cumulative(points);

  /// Further than this from the road counts as away from it, once the
  /// road has been joined. Before that, it is this much further than at
  /// the start: a route begins on the nearest road, and a car park or
  /// track can be well off it.
  static const offRouteMeters = 50.0;

  /// Away for this long before saying so: one wild fix is not a detour.
  static const offRouteAfter = Duration(seconds: 20);

  /// This close to the destination is there.
  static const arrivedWithin = 50.0;

  /// Fixes vaguer than this neither start nor end being off the road.
  static const trustedAccuracy = 50.0;

  /// Candidate places on the road within this much of the nearest are
  /// equally likely; the one closest to the last is taken, so a road that
  /// runs out and back along itself is followed, not jumped across.
  static const _ambiguousWithin = 20.0;

  final RouteKind kind;
  final double meters;
  final double? seconds;
  final (double, double) destination;
  final List<(double, double)> _points;
  final List<double> _along;

  double? _lastAlong;

  /// How far off the road the journey began; zero once on it.
  double? _startedAway;
  DateTime? _awaySince;
  bool _offRoute = false;
  bool _arrived = false;

  static List<double> _cumulative(List<(double, double)> points) {
    final along = <double>[0];
    for (var i = 1; i < points.length; i++) {
      final (lat1, lon1) = points[i - 1];
      final (lat2, lon2) = points[i];
      along.add(along.last + metersBetween(lat1, lon1, lat2, lon2));
    }
    return along;
  }

  RouteProgress update(Fix fix) {
    final straight = metersBetween(
      fix.latitude,
      fix.longitude,
      destination.$1,
      destination.$2,
    );
    _arrived = _arrived || straight <= arrivedWithin;
    if (_arrived) return const RouteProgress(metersLeft: 0, arrived: true);

    final total = _along.last;
    if (kind == RouteKind.straight || _points.length < 2 || total <= 0) {
      return RouteProgress(metersLeft: straight);
    }

    final (along, away) = _locate(fix);
    final trusted = (fix.accuracy ?? 0) <= trustedAccuracy;
    if (trusted) {
      final startedAway = _startedAway ??= away;
      if (away <= offRouteMeters) _startedAway = 0;
      if (away > offRouteMeters + startedAway) {
        _awaySince ??= fix.time;
        _offRoute = fix.time.difference(_awaySince!) >= offRouteAfter;
      } else {
        _awaySince = null;
        _offRoute = false;
      }
    }
    if (_offRoute) return RouteProgress(metersLeft: straight, offRoute: true);

    if (trusted && away <= offRouteMeters + (_startedAway ?? 0)) {
      _lastAlong = along;
    }
    final share = ((total - (_lastAlong ?? along)) / total).clamp(0.0, 1.0);
    final seconds = this.seconds;
    return RouteProgress(
      metersLeft: meters * share,
      secondsLeft: seconds == null ? null : seconds * share,
    );
  }

  /// Where on the road [fix] lies (metres from the start) and how far from
  /// it.
  (double, double) _locate(Fix fix) {
    const toRadians = pi / 180;
    final lat0 = fix.latitude;
    final lon0 = fix.longitude;
    final kx = earthRadius * toRadians * cos(lat0 * toRadians);
    const ky = earthRadius * toRadians;

    final candidates = <(double, double)>[];
    var nearest = double.infinity;
    for (var i = 1; i < _points.length; i++) {
      final ax = (_points[i - 1].$2 - lon0) * kx;
      final ay = (_points[i - 1].$1 - lat0) * ky;
      final dx = (_points[i].$2 - lon0) * kx - ax;
      final dy = (_points[i].$1 - lat0) * ky - ay;
      final length2 = dx * dx + dy * dy;
      // The fix is the origin of the plane.
      final t = length2 == 0
          ? 0.0
          : ((-ax * dx - ay * dy) / length2).clamp(0.0, 1.0);
      final away = sqrt(pow(ax + t * dx, 2) + pow(ay + t * dy, 2));
      final along = _along[i - 1] + t * (_along[i] - _along[i - 1]);
      candidates.add((along, away));
      nearest = min(nearest, away);
    }
    final last = _lastAlong;
    var best = candidates.first;
    for (final candidate in candidates) {
      final (along, away) = candidate;
      if (away > nearest + _ambiguousWithin) continue;
      final better = last == null
          ? away < best.$2
          : best.$2 > nearest + _ambiguousWithin ||
                (along - last).abs() < (best.$1 - last).abs();
      if (better) best = candidate;
    }
    return best;
  }
}
