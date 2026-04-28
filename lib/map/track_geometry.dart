import 'dart:math';

import '../journey/journey.dart';

/// Metres per pixel at zoom 0 on the equator in MapLibre's 512-pixel world.
const _metersPerPixelAtZoom0 = 2 * pi * 6378137 / 512;

/// 2^22: the scale between zoom 0 and zoom 22.
const _zoom22Scale = 4194304;

/// MapLibre expression for a circle radius that keeps its true ground size
/// at every zoom, from the feature's `radiusZ0` (pixels at zoom 0).
const List<Object> groundRadius = [
  'interpolate',
  ['exponential', 2],
  ['zoom'],
  0,
  ['get', 'radiusZ0'],
  22,
  [
    '*',
    ['get', 'radiusZ0'],
    _zoom22Scale,
  ],
];

/// Pixels at zoom 0 covered by [meters] at [latitude]; the radius doubles
/// with every zoom level.
double radiusAtZoom0(double meters, double latitude) =>
    meters / (_metersPerPixelAtZoom0 * cos(latitude * pi / 180));

Map<String, Object> _collection(List<Object> features) => {
  'type': 'FeatureCollection',
  'features': features,
};

/// One line per recorded segment. Segments are never joined: nothing is known
/// about the way between them.
Map<String, Object> trackFeatures(Iterable<List<Fix>> segments) => _collection([
  for (final segment in segments)
    if (segment.length >= 2)
      {
        'type': 'Feature',
        'properties': const <String, Object>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final fix in segment) [fix.longitude, fix.latitude],
          ],
        },
      },
]);

/// The device's position with its accuracy circle. A stale or imprecise
/// position is drawn hollow so it never reads as live and exact.
Map<String, Object> positionFeatures(
  Fix? fix, {
  required bool stale,
  required double maxAccuracy,
}) {
  if (fix == null) return _collection(const []);
  final accuracy = fix.accuracy ?? maxAccuracy;
  return _collection([
    {
      'type': 'Feature',
      'properties': {
        'radiusZ0': radiusAtZoom0(accuracy, fix.latitude),
        'hollow': stale || accuracy > maxAccuracy,
        'stale': stale,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [fix.longitude, fix.latitude],
      },
    },
  ]);
}

/// The journey's track as the map draws it. Recent fixes form a small tail
/// that is resent with every fix; older ones move into a history that is
/// resent only occasionally, so the cost per fix stays flat on long journeys.
class TrackBuffer {
  /// Tail fixes beyond which the tail is folded into history.
  static const tailLimit = 60;

  final List<List<Fix>> _segments = [];

  /// Fixes of the last segment already in history.
  int _folded = 0;

  List<List<Fix>> get segments => _segments;

  Fix? get lastFix => _segments
      .lastWhere((segment) => segment.isNotEmpty, orElse: () => const [])
      .lastOrNull;

  /// Replaces everything with a stored track.
  void reset(List<List<Fix>> track) {
    _segments
      ..clear()
      ..addAll([
        for (final segment in track) [...segment],
      ]);
    _folded = _segments.isEmpty ? 0 : _segments.last.length;
  }

  void startSegment() {
    _segments.add([]);
    _folded = 0;
  }

  void add(Fix fix) {
    if (_segments.isEmpty) startSegment();
    _segments.last.add(fix);
  }

  bool get tailIsLong =>
      _segments.isNotEmpty && _segments.last.length - _folded > tailLimit;

  void foldTail() => _folded = _segments.isEmpty ? 0 : _segments.last.length;

  /// Everything except the unfolded tail.
  Iterable<List<Fix>> get history => [
    ..._segments.take(max(0, _segments.length - 1)),
    if (_segments.isNotEmpty) _segments.last.sublist(0, _folded),
  ];

  /// The unfolded fixes of the last segment, starting with the last folded
  /// one so the line stays continuous.
  List<Fix> get tail => _segments.isEmpty
      ? const []
      : _segments.last.sublist(max(0, _folded - 1));
}
