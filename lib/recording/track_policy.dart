import 'dart:math';

import '../journey/geo.dart';
import '../journey/journey.dart';

/// How fixes are judged for one journey mode.
///
/// The values are first estimates validated on synthetic traces (see
/// test/support/traces.dart); field recordings in R4 may retune them.
class TrackPolicy {
  const TrackPolicy({
    required this.maxAccuracy,
    required this.gateFactor,
    required this.minGate,
    required this.maxSpeed,
    required this.minMovingSpeed,
    required this.driftSpeed,
    required this.confidentSpeed,
    required this.movingGateFactor,
    required this.relocateAfter,
  });

  static const road = TrackPolicy(
    maxAccuracy: 50,
    gateFactor: 4,
    minGate: 10,
    maxSpeed: 85,
    minMovingSpeed: 1,
    driftSpeed: 2,
    confidentSpeed: 2,
    movingGateFactor: 2,
    relocateAfter: 3,
  );

  static const expedition = TrackPolicy(
    maxAccuracy: 50,
    gateFactor: 4,
    minGate: 5,
    maxSpeed: 50,
    minMovingSpeed: 0.4,
    driftSpeed: 2,
    confidentSpeed: 0.8,
    movingGateFactor: 2,
    relocateAfter: 3,
  );

  static TrackPolicy of(JourneyMode mode) => switch (mode) {
    JourneyMode.road => road,
    JourneyMode.expedition => expedition,
  };

  /// Fixes less accurate than this many metres stay out of the track.
  final double maxAccuracy;

  /// Movement counts as distance only beyond this multiple of the worse
  /// accuracy of the two fixes compared. Four keeps a phone lying still for
  /// half an hour at ±25 m from inventing distance.
  final double gateFactor;

  /// Lower bound for the gate, in metres, for very accurate fixes.
  final double minGate;

  /// Metres per second beyond which a move is not believable, after giving
  /// both fixes the benefit of their stated accuracy.
  final double maxSpeed;

  /// Slowest pace in metres per second still treated as moving. Bounds how
  /// much of a stop can leak into moving time.
  final double minMovingSpeed;

  /// Moves slower than this many metres per second are ambiguous: GPS error
  /// can wander that fast. Such a move is not counted when the fix reports
  /// a speed below [minMovingSpeed].
  final double driftSpeed;

  /// Metres per second which, reported on two consecutive fixes, show the
  /// device is clearly moving. Drift is then not the risk the large gate
  /// guards against, so [movingGate] applies instead.
  final double confidentSpeed;

  /// While clearly moving, a move counts beyond this multiple of the newest
  /// fix's accuracy. Only that fix's accuracy counts, so a poor first fix
  /// after a start (GPS warming up) cannot hold back the whole walk (D-016).
  final double movingGateFactor;

  /// Consecutive, mutually consistent implausible fixes needed to accept
  /// that the device really is somewhere new, for example after a long loss
  /// of signal.
  final int relocateAfter;

  /// The stated accuracy, or the worst acceptable one if none was given.
  double accuracyOf(Fix fix) => fix.accuracy ?? maxAccuracy;

  /// The smallest movement from [anchor] to [fix] that counts as distance.
  double gateBetween(Fix anchor, Fix fix) =>
      max(minGate, gateFactor * max(accuracyOf(anchor), accuracyOf(fix)));

  /// The smallest movement that counts while the device is clearly moving.
  double movingGate(Fix fix) =>
      max(minGate, movingGateFactor * accuracyOf(fix));

  /// Whether both fixes report a speed of at least [confidentSpeed].
  bool isClearlyMoving(Fix previous, Fix fix) =>
      (previous.speed ?? 0) >= confidentSpeed &&
      (fix.speed ?? 0) >= confidentSpeed;

  /// Whether getting from [from] to [to] is physically believable.
  bool isPlausible(Fix from, Fix to) {
    final seconds = to.time.difference(from.time).inMicroseconds / 1e6;
    final slack = accuracyOf(from) + accuracyOf(to);
    return from.metersTo(to) - slack <= maxSpeed * seconds;
  }
}
