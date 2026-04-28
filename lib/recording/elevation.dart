import 'dart:math';

import '../journey/journey.dart';

/// Climb and descent from GPS altitude, counted only beyond its noise.
///
/// GPS altitude errs by metres and wanders: summing every change would turn
/// a flat walk into a mountain. So:
/// - only fixes that state a vertical accuracy, at most
///   [maxVerticalAccuracy], are used; without one the climb is unknown, not
///   zero;
/// - altitudes are averaged over the last [smoothing] usable fixes;
/// - climbs and descents are measured between turning points: a climb
///   starts once the height is a band above the last turning point, and ends
///   at its highest point once the height has fallen a band below it (and
///   the same downwards). The band is [bandPerAccuracy] times the fix's
///   vertical accuracy, at least [minBand] metres. A climb under way counts
///   up to its highest point so far; noise around a level never counts;
/// - nothing is counted across segment breaks.
///
/// On synthetic traces (E-022, GPS height error wandering over a minute):
/// a flat hour adds about 1 m on average (rarely up to a band); 100–300 m
/// climbs count within 10 %; hills not much taller than the band are
/// undercounted, because the GPS cannot resolve them either.
///
/// Like distance, the result depends only on the stored fixes, so replaying
/// a track reproduces the live numbers.
class ElevationCounter {
  static const maxVerticalAccuracy = 20.0;
  static const smoothing = 10;
  static const bandPerAccuracy = 5.0;
  static const minBand = 8.0;

  final _recent = <double>[];

  /// The last confirmed turning point, the highest or lowest height since,
  /// and which way the height is going: +1 up, -1 down, 0 not yet known.
  double? _turn;
  double _extreme = 0;
  int _direction = 0;

  double _climb = 0;
  double _descent = 0;
  bool _known = false;

  /// The climb or descent under way, up to its highest or lowest point.
  double get _pending => _turn == null ? 0 : (_extreme - _turn!).abs();

  /// Metres climbed, or null when no fix had a usable altitude.
  double? get climb => _known ? _climb + (_direction > 0 ? _pending : 0) : null;

  /// Metres descended, or null when no fix had a usable altitude.
  double? get descent =>
      _known ? _descent + (_direction < 0 ? _pending : 0) : null;

  /// The smoothed altitude of the latest usable fix, for profiles.
  double? get smoothed =>
      _recent.isEmpty ? null : _recent.reduce((a, b) => a + b) / _recent.length;

  void startSegment() {
    // The climb or descent under way ends where the segment did.
    if (_direction > 0) _climb += _pending;
    if (_direction < 0) _descent += _pending;
    _recent.clear();
    _turn = null;
    _direction = 0;
  }

  /// Whether [fix] states an altitude good enough to count.
  static bool usable(Fix fix) =>
      fix.altitude != null &&
      fix.altitudeAccuracy != null &&
      fix.altitudeAccuracy! <= maxVerticalAccuracy;

  /// Takes the next stored fix; returns whether its altitude was used.
  bool add(Fix fix) {
    if (!usable(fix)) return false;
    final altitude = fix.altitude!;
    final vertical = fix.altitudeAccuracy!;
    _known = true;
    _recent.add(altitude);
    if (_recent.length > smoothing) _recent.removeAt(0);
    final height = smoothed!;
    final turn = _turn;
    if (turn == null) {
      _turn = height;
      _extreme = height;
      return true;
    }
    final band = max(minBand, bandPerAccuracy * vertical);
    switch (_direction) {
      case 0:
        if ((height - turn).abs() >= band) {
          _direction = height > turn ? 1 : -1;
          _extreme = height;
        }
      case > 0:
        if (height > _extreme) {
          _extreme = height;
        } else if (_extreme - height >= band) {
          _climb += _extreme - turn;
          _turn = _extreme;
          _direction = -1;
          _extreme = height;
        }
      default:
        if (height < _extreme) {
          _extreme = height;
        } else if (height - _extreme >= band) {
          _descent += turn - _extreme;
          _turn = _extreme;
          _direction = 1;
          _extreme = height;
        }
    }
    return true;
  }
}
