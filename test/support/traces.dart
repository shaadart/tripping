import 'dart:math';

import 'package:tripping/journey/geo.dart';
import 'package:tripping/journey/journey.dart';

/// Ratio between the 68 % radius of a circular 2D Gaussian and its per-axis
/// standard deviation: sqrt(-2 ln 0.32).
const _radius68PerSigma = 1.5096;

/// Builds synthetic GPS traces with a realistic error model.
///
/// Position error is a first-order Gauss–Markov process (an error that
/// wanders slowly, the standard model for GNSS position error) plus a little
/// white noise. It is scaled so that the stated accuracy is the 68 % radius,
/// as Android reports it.
///
/// Reported speed models GNSS Doppler velocity: the true velocity plus small
/// independent noise, unaffected by the position error. With
/// [reportsSpeed] false, fixes carry no speed, as from providers without
/// Doppler.
///
/// [trueMeters] is the distance actually covered between the first and the
/// last fix: no fix can observe movement before the first one.
class TraceBuilder {
  TraceBuilder({
    required int seed,
    required this.accuracy,
    this.reportsSpeed = true,
    this.correlationTime = const Duration(seconds: 60),
    this.whiteNoise = 1.0,
    this.dopplerNoise = 0.1,
  }) : _random = Random(seed) {
    _errorEast = _gaussian() * _sigma;
    _errorNorth = _gaussian() * _sigma;
  }

  static const _originLat = 32.2432;
  static const _originLon = 77.1892;

  /// Stated 68 % accuracy radius in metres for every fix.
  double accuracy;
  final bool reportsSpeed;
  final Duration correlationTime;

  /// Per-axis standard deviation of the uncorrelated position noise, metres.
  final double whiteNoise;

  /// Per-axis standard deviation of the reported velocity, metres per second.
  final double dopplerNoise;

  final Random _random;
  final fixes = <Fix>[];
  DateTime time = DateTime.utc(2026, 10, 27, 6);
  double east = 0;
  double north = 0;
  double trueMeters = 0;
  double _velocityEast = 0;
  double _velocityNorth = 0;
  late double _errorEast;
  late double _errorNorth;

  double get _sigma => accuracy / _radius68PerSigma;

  /// Moves at [speed] m/s towards [heading] (degrees from north) for
  /// [duration], recording a fix every [interval].
  void move({
    required Duration duration,
    double speed = 0,
    double heading = 0,
    Duration interval = const Duration(seconds: 1),
  }) {
    final steps = duration.inMicroseconds ~/ interval.inMicroseconds;
    final seconds = interval.inMicroseconds / 1e6;
    final radians = heading * pi / 180;
    _velocityEast = sin(radians) * speed;
    _velocityNorth = cos(radians) * speed;
    for (var i = 0; i < steps; i++) {
      east += _velocityEast * seconds;
      north += _velocityNorth * seconds;
      if (fixes.isNotEmpty) trueMeters += speed * seconds;
      _advance(interval);
      fixes.add(_fixAt(east + _errorEast, north + _errorNorth));
    }
  }

  void stay(Duration duration) => move(duration: duration);

  /// Loses signal for [duration] while the device moves the given metres.
  /// The straight line counts towards [trueMeters].
  void gap(Duration duration, {double east = 0, double north = 0}) {
    this.east += east;
    this.north += north;
    if (fixes.isNotEmpty) trueMeters += sqrt(east * east + north * north);
    _advance(duration);
  }

  /// One wild fix [meters] east of the true position that still claims the
  /// normal accuracy. Takes the next time slot.
  void outlier(double meters, {Duration after = const Duration(seconds: 1)}) {
    _advance(after);
    fixes.add(_fixAt(east + meters, north));
  }

  void _advance(Duration step) {
    time = time.add(step);
    final decay = exp(-step.inMicroseconds / correlationTime.inMicroseconds);
    final innovation = sqrt(1 - decay * decay) * _sigma;
    _errorEast = decay * _errorEast + innovation * _gaussian();
    _errorNorth = decay * _errorNorth + innovation * _gaussian();
  }

  Fix _fixAt(double east, double north) {
    final noisyEast = east + whiteNoise * _gaussian();
    final noisyNorth = north + whiteNoise * _gaussian();
    final latitude = _originLat + noisyNorth / earthRadius * 180 / pi;
    final longitude =
        _originLon +
        noisyEast / (earthRadius * cos(_originLat * pi / 180)) * 180 / pi;
    final speed = reportsSpeed
        ? sqrt(
            pow(_velocityEast + dopplerNoise * _gaussian(), 2) +
                pow(_velocityNorth + dopplerNoise * _gaussian(), 2),
          )
        : null;
    return Fix(
      time: time,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
    );
  }

  double _gaussian() {
    // Box–Muller.
    final u = 1 - _random.nextDouble();
    final v = _random.nextDouble();
    return sqrt(-2 * log(u)) * cos(2 * pi * v);
  }
}
