import 'dart:math';

import 'journey.dart';

/// Mean Earth radius in metres (IUGG).
const earthRadius = 6371008.8;

/// Great-circle distance in metres (haversine on a sphere). Within about
/// 0.5 % of the ellipsoidal distance, far below GPS error.
double metersBetween(double lat1, double lon1, double lat2, double lon2) {
  const toRadians = pi / 180;
  final sinHalfDLat = sin((lat2 - lat1) * toRadians / 2);
  final sinHalfDLon = sin((lon2 - lon1) * toRadians / 2);
  final h =
      sinHalfDLat * sinHalfDLat +
      cos(lat1 * toRadians) * cos(lat2 * toRadians) * sinHalfDLon * sinHalfDLon;
  return 2 * earthRadius * asin(sqrt(min(1.0, h)));
}

extension FixGeometry on Fix {
  double metersTo(Fix other) =>
      metersBetween(latitude, longitude, other.latitude, other.longitude);
}
