import 'dart:math';

import '../journey/geo.dart';
import '../journey/journey.dart';

/// Where companions are along a planned road, and who has stopped (G6).
///
/// Pure Dart; projections on a local flat plane, far finer than GPS error
/// over a road segment.
class Convoy {
  Convoy(this.route) : _along = _cumulative(route);

  /// The way this phone is following.
  final List<(double, double)> route;
  final List<double> _along;

  /// Further than this from the route, "ahead" or "behind" would mislead.
  static const onRouteWithin = 200.0;

  static List<double> _cumulative(List<(double, double)> points) {
    final along = <double>[0];
    for (var i = 1; i < points.length; i++) {
      final (lat1, lon1) = points[i - 1];
      final (lat2, lon2) = points[i];
      along.add(along.last + metersBetween(lat1, lon1, lat2, lon2));
    }
    return along;
  }

  /// Metres from the route's start to the nearest point to [fix], or null
  /// when [fix] is more than [onRouteWithin] off the route.
  double? alongOf(Fix fix) {
    if (route.length < 2) return null;
    const toRadians = pi / 180;
    final kx = earthRadius * toRadians * cos(fix.latitude * toRadians);
    const ky = earthRadius * toRadians;
    var best = double.infinity;
    double? along;
    for (var i = 1; i < route.length; i++) {
      final ax = (route[i - 1].$2 - fix.longitude) * kx;
      final ay = (route[i - 1].$1 - fix.latitude) * ky;
      final dx = (route[i].$2 - fix.longitude) * kx - ax;
      final dy = (route[i].$1 - fix.latitude) * ky - ay;
      final length2 = dx * dx + dy * dy;
      final t = length2 == 0
          ? 0.0
          : ((-ax * dx - ay * dy) / length2).clamp(0.0, 1.0);
      final away = sqrt(pow(ax + t * dx, 2) + pow(ay + t * dy, 2));
      if (away < best) {
        best = away;
        along = _along[i - 1] + t * (_along[i] - _along[i - 1]);
      }
    }
    return best <= onRouteWithin ? along : null;
  }

  /// "1.2 km ahead", "600 m behind" or "alongside" from [me] to [them]
  /// along the route; null when either is off it.
  String? gapText(Fix me, Fix them) {
    final (mine, theirs) = (alongOf(me), alongOf(them));
    if (mine == null || theirs == null) return null;
    final gap = theirs - mine;
    if (gap.abs() < 50) return 'alongside';
    final meters = gap.abs();
    final distance = meters < 950
        ? '${(meters / 10).round() * 10} m'
        : '${(meters / 1000).toStringAsFixed(meters < 9950 ? 1 : 0)} km';
    return '$distance ${gap > 0 ? 'ahead' : 'behind'}';
  }
}

/// Notices a companion standing still: within [radius] of one spot for
/// longer than [after], by the times of their positions.
class Stillness {
  Stillness({this.radius = 30, this.after = const Duration(minutes: 2)});

  final double radius;
  final Duration after;
  Fix? _spot;
  DateTime? _since;

  /// Takes their newest position, taken at [at]; returns since when they
  /// have stood still, once that is longer than [after], else null.
  DateTime? update(Fix fix, DateTime at) {
    final spot = _spot;
    if (spot == null || spot.metersTo(fix) > radius) {
      _spot = fix;
      _since = at;
      return null;
    }
    final since = _since!;
    return at.difference(since) > after ? since : null;
  }
}
