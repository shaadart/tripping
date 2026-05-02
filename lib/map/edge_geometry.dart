import 'dart:math';
import 'dart:ui';

/// A companion as the map projects it onto the screen, in logical pixels.
/// [at] may lie far outside the screen, or be unusable (not finite) when the
/// camera cannot project it; then [direction] (radians, screen angle, 0 =
/// up, clockwise) says which way they are.
class EdgeTarget {
  const EdgeTarget(this.id, this.at, {this.direction});

  final String id;
  final Offset at;
  final double? direction;
}

/// Where to draw a bubble for one or more companions who are off the map:
/// its [centre] on the edge of the usable area, and the [angle] its pointer
/// takes towards them (radians, screen angle, 0 = up, clockwise).
class EdgeBubble {
  const EdgeBubble(this.ids, this.centre, this.angle);

  final List<String> ids;
  final Offset centre;
  final double angle;
}

/// Places a bubble on the edge of [usable] for every target that cannot be
/// seen: outside it, or under one of [occluders] (toolbar, buttons). Bubbles
/// of [radius] keep clear of the occluders by sliding along their edge, and
/// bubbles closer than [minGap] merge into one for the group. The same input
/// always gives the same output, so bubbles do not jitter.
List<EdgeBubble> placeEdgeBubbles({
  required Rect usable,
  required List<EdgeTarget> targets,
  List<Rect> occluders = const [],
  double radius = 24,
  double minGap = 56,
}) {
  final track = usable.deflate(radius + 4);
  if (track.width <= 0 || track.height <= 0) return const [];
  bool covered(Offset p) =>
      occluders.any((r) => r.inflate(radius + 4).contains(p));

  final placed = <({String id, double s, double angle})>[];
  for (final target in targets) {
    final at = target.at;
    final finite = at.dx.isFinite && at.dy.isFinite;
    if (finite &&
        usable.contains(at) &&
        !occluders.any((r) => r.contains(at))) {
      continue;
    }
    final angle = finite && at != usable.center
        ? _screenAngle(at - usable.center)
        : target.direction;
    if (angle == null) continue;
    final onEdge = _rayToBorder(track, angle);
    final s = _slide(track, _perimeterOf(track, onEdge), covered);
    if (s == null) continue;
    final centre = _pointAt(track, s);
    placed.add((
      id: target.id,
      s: s,
      angle: finite ? _screenAngle(at - centre) : angle,
    ));
  }
  if (placed.isEmpty) return const [];

  // Walk the border once, in order, merging neighbours that would touch.
  placed.sort(
    (a, b) =>
        a.s.compareTo(b.s) != 0 ? a.s.compareTo(b.s) : a.id.compareTo(b.id),
  );
  final perimeter = 2 * (track.width + track.height);
  final groups = <List<({String id, double s, double angle})>>[];
  for (final p in placed) {
    final last = groups.lastOrNull;
    if (last != null && p.s - last.last.s < minGap) {
      last.add(p);
    } else {
      groups.add([p]);
    }
  }
  // The border is a loop: the last group may touch the first.
  if (groups.length > 1 &&
      groups.first.first.s + perimeter - groups.last.last.s < minGap) {
    groups.first.insertAll(0, groups.removeLast());
  }
  return [
    for (final group in groups)
      () {
        // The group sits at the middle of its members along the border,
        // pointing their average way.
        final first = group.first.s;
        var sum = 0.0;
        var x = 0.0, y = 0.0;
        for (final m in group) {
          var s = m.s;
          if (s < first) s += perimeter;
          sum += s;
          x += sin(m.angle);
          y += cos(m.angle);
        }
        final s =
            _slide(track, (sum / group.length) % perimeter, covered) ??
            group.first.s;
        return EdgeBubble(
          [for (final m in group) m.id],
          _pointAt(track, s),
          atan2(x, y),
        );
      }(),
  ];
}

/// Screen angle of [v]: 0 = up, clockwise, in (-pi, pi].
double _screenAngle(Offset v) => atan2(v.dx, -v.dy);

/// Where a ray from the centre of [r] at [angle] leaves it.
Offset _rayToBorder(Rect r, double angle) {
  final dx = sin(angle), dy = -cos(angle);
  final c = r.center;
  final tx = dx == 0 ? double.infinity : (r.width / 2) / dx.abs();
  final ty = dy == 0 ? double.infinity : (r.height / 2) / dy.abs();
  final t = min(tx, ty);
  return Offset(
    (c.dx + dx * t).clamp(r.left, r.right),
    (c.dy + dy * t).clamp(r.top, r.bottom),
  );
}

/// Distance along the border of [r], clockwise from its top-left corner, of
/// [p] (a point on the border).
double _perimeterOf(Rect r, Offset p) {
  final w = r.width, h = r.height;
  const e = 0.001;
  if ((p.dy - r.top).abs() < e) return p.dx - r.left;
  if ((p.dx - r.right).abs() < e) return w + (p.dy - r.top);
  if ((p.dy - r.bottom).abs() < e) return w + h + (r.right - p.dx);
  return 2 * w + h + (r.bottom - p.dy);
}

/// The point at distance [s] along the border of [r] (see [_perimeterOf]).
Offset _pointAt(Rect r, double s) {
  final w = r.width, h = r.height;
  s %= 2 * (w + h);
  if (s <= w) return Offset(r.left + s, r.top);
  if (s <= w + h) return Offset(r.right, r.top + s - w);
  if (s <= 2 * w + h) return Offset(r.right - (s - w - h), r.bottom);
  return Offset(r.left, r.bottom - (s - 2 * w - h));
}

/// The nearest free place along the border to [s], or null when all of it
/// is covered.
double? _slide(Rect r, double s, bool Function(Offset) covered) {
  final perimeter = 2 * (r.width + r.height);
  for (var d = 0.0; d <= perimeter / 2; d += 4) {
    for (final candidate in [s + d, s - d]) {
      final at = (candidate % perimeter + perimeter) % perimeter;
      if (!covered(_pointAt(r, at))) return at;
    }
  }
  return null;
}

/// Whether a projected position [at] disagrees with the companion's
/// [direction] from [centre] by more than a right angle: a tilted camera
/// mirrors places behind it onto the far side of the screen, so then the
/// direction is believed instead.
bool looksMirrored(Offset at, Offset centre, double direction) {
  final v = at - centre;
  if (!v.dx.isFinite || !v.dy.isFinite || v.distance <= 1) return false;
  return cos(_screenAngle(v) - direction) < 0;
}
