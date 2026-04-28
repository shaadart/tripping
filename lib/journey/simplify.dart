import 'dart:math';
import 'dart:typed_data';

import 'journey.dart';

const _earthRadius = 6371008.8;

/// The fewest fixes of [line] that keep every dropped fix within [tolerance]
/// metres of the simplified line (Douglas–Peucker). The first and last fixes
/// are always kept, so the line still starts and ends where it did.
///
/// Distances are measured on a local plane around the first fix, which is
/// exact enough for a tolerance over a journey's extent.
List<Fix> simplify(List<Fix> line, double tolerance) {
  final n = line.length;
  if (n < 3) return [...line];
  final latitude0 = line.first.latitude;
  final longitude0 = line.first.longitude;
  final metersPerDegree = _earthRadius * pi / 180;
  final eastScale = metersPerDegree * cos(latitude0 * pi / 180);
  final xs = Float64List(n);
  final ys = Float64List(n);
  for (var i = 0; i < n; i++) {
    xs[i] = (line[i].longitude - longitude0) * eastScale;
    ys[i] = (line[i].latitude - latitude0) * metersPerDegree;
  }

  final keep = List.filled(n, false)
    ..[0] = true
    ..[n - 1] = true;
  // An explicit stack: a 24-hour track is too deep for recursion.
  final stack = [(0, n - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var worst = -1;
    var worstDistance = tolerance;
    for (var i = a + 1; i < b; i++) {
      final distance = _toSegment(xs, ys, i, a, b);
      if (distance > worstDistance) {
        worst = i;
        worstDistance = distance;
      }
    }
    if (worst >= 0) {
      keep[worst] = true;
      stack
        ..add((a, worst))
        ..add((worst, b));
    }
  }
  return [
    for (var i = 0; i < n; i++)
      if (keep[i]) line[i],
  ];
}

/// Distance from point [i] to the segment from [a] to [b].
double _toSegment(Float64List xs, Float64List ys, int i, int a, int b) {
  final dx = xs[b] - xs[a];
  final dy = ys[b] - ys[a];
  final lengthSquared = dx * dx + dy * dy;
  final t = lengthSquared == 0
      ? 0.0
      : (((xs[i] - xs[a]) * dx + (ys[i] - ys[a]) * dy) / lengthSquared).clamp(
          0.0,
          1.0,
        );
  final ex = xs[a] + t * dx - xs[i];
  final ey = ys[a] + t * dy - ys[i];
  return sqrt(ex * ex + ey * ey);
}
