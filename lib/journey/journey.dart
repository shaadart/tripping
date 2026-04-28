import 'package:drift/drift.dart';

/// How a journey is undertaken. Modes share recording machinery but differ in
/// sampling policy, map treatment and primary actions.
enum JourneyMode { road, expedition }

/// Persisted lifecycle of a journey.
///
/// "Interrupted" is deliberately not a status: it is a fact about the last
/// segment (see [SegmentEnd.interrupted]) of a journey that is now [paused].
enum JourneyStatus { recording, paused, ended }

/// Why a continuous stretch of recording stopped.
enum SegmentEnd {
  /// The user paused.
  paused,

  /// The user ended the journey.
  ended,

  /// Recording stopped without the user asking (process killed, crash).
  /// The segment's end time is the last fix we can vouch for.
  interrupted,
}

/// Where a waypoint came from.
enum WaypointKind {
  /// The device's own position when the user marked it: carries the fix's
  /// accuracy and time.
  marked,

  /// A place the user chose on the map. Nobody has been there yet.
  planned,
}

/// How a route to a destination was made.
enum RouteKind {
  /// Along roads or paths, from a routing service.
  road,

  /// A straight line, when no road route could be had. Never drawn or
  /// described as a road.
  straight,
}

/// One location fix as reported by the device. All times are UTC.
class Fix {
  const Fix({
    required this.time,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.altitudeAccuracy,
    this.speed,
    this.heading,
  });

  /// When the device determined the position (not when we received it).
  final DateTime time;
  final double latitude;
  final double longitude;

  /// Horizontal accuracy radius in metres.
  final double? accuracy;

  /// Metres above the WGS84 ellipsoid or mean sea level, as the platform
  /// reports it.
  final double? altitude;
  final double? altitudeAccuracy;

  /// Metres per second.
  final double? speed;

  /// Degrees clockwise from true north.
  final double? heading;

  @override
  bool operator ==(Object other) =>
      other is Fix &&
      other.time == time &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracy == accuracy &&
      other.altitude == altitude &&
      other.altitudeAccuracy == altitudeAccuracy &&
      other.speed == speed &&
      other.heading == heading;

  @override
  int get hashCode => Object.hash(
    time,
    latitude,
    longitude,
    accuracy,
    altitude,
    altitudeAccuracy,
    speed,
    heading,
  );

  @override
  String toString() => 'Fix($time, $latitude, $longitude, ±$accuracy m)';
}

/// Stores a [WaypointKind] by name, so reordering the enum never changes
/// what stored waypoints mean.
class WaypointKindByName extends EnumNameConverter<WaypointKind> {
  const WaypointKindByName() : super(WaypointKind.values);
}

/// Stores a [RouteKind] by name, like [WaypointKindByName].
class RouteKindByName extends EnumNameConverter<RouteKind> {
  const RouteKindByName() : super(RouteKind.values);
}

/// Stores instants as UTC milliseconds since the epoch.
///
/// Drift's default DateTime storage has one-second resolution, which would
/// collapse consecutive GPS fixes.
class UtcMillis extends TypeConverter<DateTime, int> {
  const UtcMillis();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}
