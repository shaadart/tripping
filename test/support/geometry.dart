import 'package:tripping/journey/geo.dart';
import 'package:tripping/journey/journey.dart';

/// Distance from [fix] to the nearest point of [line], in metres, sampled
/// finely enough for a test.
double distanceToLine(Fix fix, List<Fix> line) {
  var best = double.infinity;
  for (var i = 0; i + 1 < line.length; i++) {
    for (var step = 0; step <= 100; step++) {
      final t = step / 100;
      final point = Fix(
        time: fix.time,
        latitude:
            line[i].latitude + t * (line[i + 1].latitude - line[i].latitude),
        longitude:
            line[i].longitude + t * (line[i + 1].longitude - line[i].longitude),
      );
      final d = fix.metersTo(point);
      if (d < best) best = d;
    }
  }
  return best;
}
