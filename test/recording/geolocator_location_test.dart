import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tripping/recording/geolocator_location.dart';
import 'package:tripping/recording/location_source.dart';

Position position({
  bool measured = true,
  double speed = 0,
  DateTime? timestamp,
}) => Position(
  latitude: 32.2432,
  longitude: 77.1892,
  timestamp: timestamp ?? DateTime.utc(2026, 10, 28, 6),
  accuracy: measured ? 4 : 0,
  altitude: measured ? 2050 : 0,
  altitudeAccuracy: measured ? 3 : 0,
  heading: 0,
  headingAccuracy: measured ? 5 : 0,
  speed: speed,
  speedAccuracy: measured ? 0.2 : 0,
  hasAccuracy: measured,
  hasAltitude: measured,
  hasAltitudeAccuracy: measured,
  hasHeading: measured,
  hasHeadingAccuracy: measured,
  hasSpeed: measured,
  hasSpeedAccuracy: measured,
);

void main() {
  test('unmeasured values become null, never zero', () {
    final fix = fixFrom(position(measured: false));

    expect(fix.speed, isNull);
    expect(fix.accuracy, isNull);
    expect(fix.altitude, isNull);
    expect(fix.altitudeAccuracy, isNull);
    expect(fix.heading, isNull);
  });

  test('measured values pass through, including a genuine zero speed', () {
    final fix = fixFrom(position());

    expect(fix.speed, 0);
    expect(fix.heading, 0);
    expect(fix.accuracy, 4);
    expect(fix.altitude, 2050);
  });

  test('fix time is UTC', () {
    final local = DateTime(2026, 10, 28, 11, 30);

    final fix = fixFrom(position(timestamp: local));

    expect(fix.time.isUtc, isTrue);
    expect(fix.time, local.toUtc());
  });

  test('permissions map to access', () {
    expect(accessFrom(LocationPermission.whileInUse), LocationAccess.granted);
    expect(accessFrom(LocationPermission.always), LocationAccess.granted);
    expect(accessFrom(LocationPermission.denied), LocationAccess.denied);
    expect(
      accessFrom(LocationPermission.deniedForever),
      LocationAccess.deniedForever,
    );
    expect(
      accessFrom(LocationPermission.unableToDetermine),
      LocationAccess.denied,
    );
  });
}
