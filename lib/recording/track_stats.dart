import 'dart:math';

import '../journey/geo.dart';
import '../journey/journey.dart';
import 'track_policy.dart';

/// Distance and moving time derived from the fixes stored for a journey.
///
/// Movement is measured from the last counted point (the anchor), not from
/// the previous fix, and counts only once it clearly exceeds the fixes'
/// stated accuracy. Noise around someone standing still therefore never
/// accumulates, while slow walking eventually crosses the gate and is
/// counted in full.
///
/// The gate is large (four times the worse accuracy) unless the device
/// reports walking or driving speed on consecutive fixes. Then it is twice
/// the newest fix's accuracy: drift is not the risk while clearly moving, and
/// a poor first fix (GPS warming up) must not hold back the whole walk.
///
/// Consequences, by design:
/// - the total trails the truth by at most one gate;
/// - path detail finer than the gate, such as tight switchbacks, is not
///   resolved. The fixes cannot resolve it either.
///
/// Moving time counts the intervals between counted moves. An interval
/// that spans a stop is charged only for its distance at the last moving
/// pace.
///
/// The result depends only on the stored fixes and segment breaks, so
/// [TrackStats.replay] reproduces live numbers exactly.
class TrackStats {
  TrackStats(this.policy);

  /// Rebuilds stats from a stored track, as returned by
  /// `JourneyStore.track`.
  factory TrackStats.replay(TrackPolicy policy, List<List<Fix>> track) {
    final stats = TrackStats(policy);
    for (final segment in track) {
      stats.startSegment();
      segment.forEach(stats.add);
    }
    return stats;
  }

  final TrackPolicy policy;
  double _meters = 0;
  Duration _movingTime = Duration.zero;
  Fix? _anchor;
  Fix? _previous;

  /// Metres per second of the last counted move that was clearly moving.
  double? _pace;

  double get meters => _meters;
  Duration get movingTime => _movingTime;

  /// Call when a segment opens: nothing is known about the way between
  /// segments, so it never counts.
  void startSegment() {
    _anchor = null;
    _previous = null;
    _pace = null;
  }

  /// Adds the next stored fix. Fixes must arrive in time order.
  void add(Fix fix) {
    final anchor = _anchor;
    final previous = _previous;
    _previous = fix;
    if (anchor == null ||
        previous == null ||
        !policy.isPlausible(previous, fix)) {
      // Segment start or relocation: start measuring afresh from here.
      _anchor = fix;
      return;
    }

    final meters = anchor.metersTo(fix);
    final gate = policy.isClearlyMoving(previous, fix)
        ? policy.movingGate(fix)
        : policy.gateBetween(anchor, fix);
    if (meters <= gate) return;
    final sinceAnchor = fix.time.difference(anchor.time);
    if (_reportsStandingStill(fix, meters, sinceAnchor)) return;

    _meters += meters;
    final seconds = sinceAnchor.inMicroseconds / 1e6;
    final pace = meters / seconds;
    if (pace >= policy.minMovingSpeed) {
      _movingTime += sinceAnchor;
      _pace = pace;
    } else {
      // The interval spans a stop. Assume this stretch was covered at the
      // last moving pace; the rest of the interval was standing still.
      final assumedPace = max(_pace ?? 0, policy.minMovingSpeed);
      _movingTime += Duration(
        microseconds: (meters / assumedPace * 1e6).round(),
      );
    }
    _anchor = fix;
  }

  /// Positions alone cannot tell slow drift from slow walking. A reported
  /// speed can, because it comes from Doppler measurements that do not share
  /// the position error. It only settles slow moves: a fast one counts
  /// whatever speed is reported.
  bool _reportsStandingStill(Fix fix, double meters, Duration sinceAnchor) {
    final speed = fix.speed;
    if (speed == null || speed >= policy.minMovingSpeed) return false;
    final seconds = sinceAnchor.inMicroseconds / 1e6;
    return meters < policy.driftSpeed * seconds;
  }
}
