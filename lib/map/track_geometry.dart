import 'dart:math';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../journey/simplify.dart';
import '../group/group_sync.dart';
import '../group/sharing.dart';

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
/// that is resent with every fix; older ones are folded into a history that
/// is simplified once and resent only at a fold, so the cost per fix stays
/// small on long journeys.
class TrackBuffer {
  TrackBuffer({this.tolerance = 2});

  /// Tail fixes beyond which the tail is folded into history, at least.
  static const tailLimit = 60;

  /// Metres a drawn history line may stray from the fixes; 2 m is under two
  /// pixels at street zoom, against a 5-pixel line.
  final double tolerance;

  final List<List<Fix>> _segments = [];

  /// Simplified fixes of every segment up to the fold.
  final List<List<Fix>> _history = [];
  int _historyPoints = 0;

  /// Fixes of the last segment already in history.
  int _folded = 0;

  /// Every recorded fix, unsimplified.
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
    _history
      ..clear()
      ..addAll([for (final segment in track) simplify(segment, tolerance)]);
    _historyPoints = _history.fold(0, (sum, s) => sum + s.length);
    _folded = _segments.isEmpty ? 0 : _segments.last.length;
  }

  void startSegment() {
    _segments.add([]);
    _history.add([]);
    _folded = 0;
  }

  void add(Fix fix) {
    if (_segments.isEmpty) startSegment();
    _segments.last.add(fix);
  }

  /// Folding resends the history, so it waits until the tail is about the
  /// square root of the history: that keeps the points sent per fix (tail
  /// plus history per fold) near their minimum.
  bool get tailIsLong =>
      _segments.isNotEmpty &&
      _segments.last.length - _folded >
          max(tailLimit, sqrt(_historyPoints).ceil());

  void foldTail() {
    if (_segments.isEmpty) return;
    final last = _segments.last;
    // The chunk starts at the last folded fix, which simplification kept as
    // an end point, so the history stays one continuous line.
    final chunk = simplify(last.sublist(max(0, _folded - 1)), tolerance);
    final drawn = _history.last;
    final added = drawn.isEmpty ? chunk : chunk.skip(1);
    drawn.addAll(added);
    _historyPoints += added.length;
    _folded = last.length;
  }

  /// Everything except the unfolded tail, simplified.
  List<List<Fix>> get history => _history;

  /// The unfolded fixes of the last segment, starting with the last folded
  /// one so the line stays continuous.
  List<Fix> get tail => _segments.isEmpty
      ? const []
      : _segments.last.sublist(max(0, _folded - 1));
}

/// The box around every fix of [track] and every point of [also], or null
/// when there are none.
({double south, double west, double north, double east})? boundsOf(
  Iterable<List<Fix>> track, {
  Iterable<(double, double)> also = const [],
}) {
  ({double south, double west, double north, double east})? box;
  void add(double latitude, double longitude) {
    final b = box;
    box = b == null
        ? (south: latitude, west: longitude, north: latitude, east: longitude)
        : (
            south: min(b.south, latitude),
            west: min(b.west, longitude),
            north: max(b.north, latitude),
            east: max(b.east, longitude),
          );
  }

  for (final segment in track) {
    for (final fix in segment) {
      add(fix.latitude, fix.longitude);
    }
  }
  for (final (latitude, longitude) in also) {
    add(latitude, longitude);
  }
  return box;
}

/// Where the journey began and where it ended, as points with an `end`
/// property of `start` or `finish`.
Map<String, Object> endsFeatures(List<List<Fix>> track) {
  final fixes = [for (final segment in track) ...segment];
  if (fixes.isEmpty) return _collection(const []);
  Map<String, Object> point(Fix fix, String end) => {
    'type': 'Feature',
    'properties': {'end': end},
    'geometry': {
      'type': 'Point',
      'coordinates': [fix.longitude, fix.latitude],
    },
  };
  return _collection([
    point(fixes.first, 'start'),
    if (fixes.length > 1) point(fixes.last, 'finish'),
  ]);
}

/// What a waypoint is called on the map and in lists: its name, or its
/// number on the journey.
String waypointLabel(WaypointRow waypoint, int index) =>
    waypoint.name ?? '${index + 1}';

/// Waypoints as points with `kind` and `label` properties.
Map<String, Object> waypointFeatures(List<WaypointRow> waypoints) =>
    _collection([
      for (final (i, waypoint) in waypoints.indexed)
        {
          'type': 'Feature',
          // Taps on the map report this id.
          'id': waypoint.id,
          'properties': {
            'kind': waypoint.kind.name,
            'label': waypointLabel(waypoint, i),
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [waypoint.longitude, waypoint.latitude],
          },
        },
    ]);

/// A planned way to a destination as a line with a `kind` property: `road`
/// or `straight` (drawn differently, never mistaken for each other).
Map<String, Object> routeFeatures(
  List<(double, double)> points,
  RouteKind kind,
) => _collection([
  if (points.length >= 2)
    {
      'type': 'Feature',
      'properties': {'kind': kind.name},
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          for (final (latitude, longitude) in points) [longitude, latitude],
        ],
      },
    },
]);

/// Where a journey is going, as a point with its `name`.
Map<String, Object> destinationFeatures(
  String name,
  double latitude,
  double longitude,
) => _collection([
  {
    'type': 'Feature',
    'properties': {'name': name},
    'geometry': {
      'type': 'Point',
      'coordinates': [longitude, latitude],
    },
  },
]);

/// Companions with a position, as points with `name`, `label` and
/// `freshness` (`live`, `aging` or `stale`, by the age of their fix at
/// [now]). Without a position, a companion is not on the map.
Map<String, Object> companionFeatures(
  List<Companion> companions,
  DateTime now,
) => _collection([
  for (final companion in companions)
    if (companion.shared case Shared(
      :final fix?,
      :final phase,
      :final mode,
    ) when phase != JourneyPhase.ended)
      () {
        final old = now.difference(companion.positionAt ?? fix.time);
        final freshness = freshnessOf(
          old.isNegative ? Duration.zero : old,
          mode,
        );
        final minutes = old.inMinutes;
        return {
          'type': 'Feature',
          'properties': {
            'name': companion.name,
            'freshness': freshness.name,
            'label': freshness == Freshness.live
                ? companion.name
                : '${companion.name} · '
                      '${minutes < 60 ? '$minutes min' : '${old.inHours} h'}',
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [fix.longitude, fix.latitude],
          },
        };
      }(),
]);
