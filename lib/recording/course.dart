import 'dart:math';

import '../journey/geo.dart';
import '../journey/journey.dart';

/// The direction of travel: the GPS's own heading when it measured one at
/// walking speed or more, else the way the last stretch of fixes went.
/// Unknown when standing, or when nothing new has come for a while.
class Course {
  Course({
    this.minSpeed = 0.5,
    this.span = 25,
    this.staleAfter = const Duration(seconds: 30),
  });

  /// Slower than this (m/s), a GPS heading is not trusted.
  final double minSpeed;

  /// Metres travelled before a direction is drawn from the fixes; more
  /// when they are vaguer, so noise is not taken for movement.
  final double span;

  /// Without a fresh direction for this long, the walker may have stopped.
  final Duration staleAfter;

  Fix? _from;
  double? _course;
  DateTime? _at;

  /// Takes the newest fix; returns the direction of travel in degrees from
  /// north, or null when it is not known.
  double? update(Fix fix) {
    final heading = fix.heading;
    if ((fix.speed ?? 0) >= minSpeed && heading != null) {
      _course = heading;
      _at = fix.time;
      _from = fix;
    } else {
      final from = _from;
      final needed = max(span, 3 * max(fix.accuracy ?? 0, from?.accuracy ?? 0));
      if (from == null || fix.time.isBefore(from.time)) {
        _from = fix;
      } else if (from.metersTo(fix) >= needed) {
        _course = from.bearingTo(fix);
        _at = fix.time;
        _from = fix;
      }
    }
    final at = _at;
    if (at != null && fix.time.difference(at) > staleAfter) _course = null;
    return _course;
  }
}
