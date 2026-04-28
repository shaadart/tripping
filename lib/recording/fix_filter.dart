import '../journey/journey.dart';
import 'track_policy.dart';

/// What [FixFilter] decided about one fix.
enum FixVerdict {
  /// Belongs in the track.
  accepted,

  /// Belongs in the track, but the device is somewhere the previous fixes
  /// cannot explain, so the way between is unknown and not counted.
  relocated,

  /// Not newer than a fix already judged: a duplicate or out of order.
  stale,

  /// The coordinates are not a real position.
  invalid,

  /// Less accurate than the mode allows.
  inaccurate,

  /// An implausible jump from the track so far. Held back in case further
  /// fixes confirm the device really moved there.
  implausible;

  bool get belongsInTrack => this == accepted || this == relocated;
}

/// Decides which fixes belong in a journey's track. Give it every fix the
/// platform reports, in arrival order.
class FixFilter {
  /// Fixes at or before [after], such as the newest one already stored for
  /// the journey, are stale.
  FixFilter(this.policy, {DateTime? after}) : _latest = after;

  final TrackPolicy policy;
  DateTime? _latest;
  Fix? _reference;
  final _suspects = <Fix>[];

  /// Call when a segment opens (resume, recovery). Movement across the
  /// break is not judged; time order still is.
  void startSegment() {
    _reference = null;
    _suspects.clear();
  }

  FixVerdict judge(Fix fix) {
    if (!_isRealPosition(fix)) return FixVerdict.invalid;
    final latest = _latest;
    if (latest != null && !fix.time.isAfter(latest)) return FixVerdict.stale;
    _latest = fix.time;
    if (policy.accuracyOf(fix) > policy.maxAccuracy) {
      return FixVerdict.inaccurate;
    }

    final reference = _reference;
    if (reference == null || policy.isPlausible(reference, fix)) {
      _suspects.clear();
      _reference = fix;
      return FixVerdict.accepted;
    }

    if (_suspects.isNotEmpty && !policy.isPlausible(_suspects.last, fix)) {
      _suspects.clear();
    }
    _suspects.add(fix);
    if (_suspects.length < policy.relocateAfter) return FixVerdict.implausible;
    _suspects.clear();
    _reference = fix;
    return FixVerdict.relocated;
  }

  static bool _isRealPosition(Fix fix) {
    final accuracy = fix.accuracy;
    return fix.latitude.isFinite &&
        fix.longitude.isFinite &&
        fix.latitude.abs() <= 90 &&
        fix.longitude.abs() <= 180 &&
        // Exactly 0,0 is a classic sign of a provider bug, not a position.
        (fix.latitude != 0 || fix.longitude != 0) &&
        (accuracy == null || (accuracy.isFinite && accuracy >= 0));
  }
}
