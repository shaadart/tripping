import 'dart:async';
import 'dart:math';

import '../journey/geo.dart';
import '../journey/journey.dart';
import 'location_source.dart';

/// Test builds only: a drive or walk round a loop at a public place, made
/// up inside the app (E-037). It never asks the phone for a position, so a
/// simulated test cannot see the real one; Google's fused provider once
/// slipped it past the adb simulator.
///
///   --dart-define=TRIPPING_SIMULATE=12.9763,77.5929,8
///
/// is a loop at Cubbon Park at 8 m/s (latitude, longitude, metres a
/// second). Unset in every normal and release build, where this is never
/// constructed.
class SimulatedLocation implements LocationSource {
  SimulatedLocation({
    required this.origin,
    this.speed = 1.4,
    this.accuracy = 5,
    DateTime Function()? clock,
    int seed = 1,
  }) : _clock = clock ?? _utcNow,
       _random = Random(seed) {
    _startedAt = _clock();
    final sigma = accuracy / 1.51;
    _errorEast = sigma * _noise();
    _errorNorth = sigma * _noise();
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  static const spec = String.fromEnvironment('TRIPPING_SIMULATE');
  static bool get enabled => spec.isNotEmpty;

  /// From "lat,lon[,speed]"; throws on anything else, so a wrong flag fails
  /// loudly instead of falling back to the real GPS.
  factory SimulatedLocation.fromSpec(String spec) {
    final parts = [for (final part in spec.split(',')) double.parse(part)];
    if (parts.length < 2 || parts[0].abs() > 90 || parts[1].abs() > 180) {
      throw FormatException('TRIPPING_SIMULATE needs lat,lon[,speed]', spec);
    }
    return SimulatedLocation(
      origin: (parts[0], parts[1]),
      speed: parts.length > 2 ? parts[2] : 1.4,
    );
  }

  /// The loop: [east] metres east, [north] north, and back, anticlockwise.
  static const east = 300.0;
  static const north = 200.0;

  final (double, double) origin;
  final double speed;
  final double accuracy;
  final DateTime Function() _clock;
  final Random _random;
  late final DateTime _startedAt;
  late double _errorEast;
  late double _errorNorth;

  double _noise() =>
      sqrt(-2 * log(1 - _random.nextDouble())) *
      cos(2 * pi * _random.nextDouble());

  @override
  Future<LocationAccess> requestAccess() async => LocationAccess.granted;

  @override
  Future<void> openSettingsFor(LocationAccess problem) async {}

  @override
  Future<Fix?> lastKnown() async => _fixAt(_clock());

  /// One fix a second, as the platform gives; never a position of the
  /// phone's own.
  @override
  Stream<Fix> watch(JourneyMode mode) =>
      Stream.periodic(const Duration(seconds: 1), (_) => _fixAt(_clock()));

  /// Where the loop puts the phone at [at], with GPS-like error that
  /// wanders slowly (first-order Gauss–Markov, 30 s), and the heading and
  /// speed of travel.
  Fix _fixAt(DateTime at) {
    const perimeter = 2 * (east + north);
    final seconds = at.difference(_startedAt).inMilliseconds / 1000;
    final along = (speed * seconds) % perimeter;
    final (x, y, heading) = along < east
        ? (along, 0.0, 90.0)
        : along < east + north
        ? (east, along - east, 0.0)
        : along < 2 * east + north
        ? (2 * east + north - along, north, 270.0)
        : (0.0, perimeter - along, 180.0);
    final sigma = accuracy / 1.51;
    final keep = exp(-1 / 30);
    final fresh = sigma * sqrt(1 - keep * keep);
    _errorEast = keep * _errorEast + fresh * _noise();
    _errorNorth = keep * _errorNorth + fresh * _noise();
    final (lat0, lon0) = origin;
    return Fix(
      time: at,
      latitude: lat0 + (y + _errorNorth) / earthRadius * 180 / pi,
      longitude:
          lon0 +
          (x + _errorEast) / (earthRadius * cos(lat0 * pi / 180)) * 180 / pi,
      accuracy: accuracy,
      speed: speed,
      heading: heading,
    );
  }
}
