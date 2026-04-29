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

/// Initial great-circle bearing from the first point to the second, in
/// degrees clockwise from north, 0 to 360.
double bearingBetween(double lat1, double lon1, double lat2, double lon2) {
  const toRadians = pi / 180;
  final phi1 = lat1 * toRadians;
  final phi2 = lat2 * toRadians;
  final dLon = (lon2 - lon1) * toRadians;
  final y = sin(dLon) * cos(phi2);
  final x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLon);
  return (atan2(y, x) / toRadians + 360) % 360;
}

extension FixGeometry on Fix {
  double metersTo(Fix other) =>
      metersBetween(latitude, longitude, other.latitude, other.longitude);

  double bearingTo(Fix other) =>
      bearingBetween(latitude, longitude, other.latitude, other.longitude);
}

/// The nearest of eight compass points for a bearing: N, NE, E, SE, S, SW,
/// W or NW.
String compassPoint(double bearing) => const [
  'N',
  'NE',
  'E',
  'SE',
  'S',
  'SW',
  'W',
  'NW',
][((bearing % 360) / 45).round() % 8];

/// Where a [bearing] lies from someone moving along [heading], in words:
/// ahead, ahead right, right, behind right, behind, behind left, left or
/// ahead left.
String relativeDirection(double bearing, double heading) => const [
  'ahead',
  'ahead right',
  'right',
  'behind right',
  'behind',
  'behind left',
  'left',
  'ahead left',
][(((bearing - heading) % 360) / 45).round() % 8];
