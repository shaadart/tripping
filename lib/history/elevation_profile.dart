import 'dart:math';

import '../journey/journey.dart';
import '../recording/elevation.dart';
import '../recording/track_policy.dart';
import '../recording/track_stats.dart';

/// A journey's climb and descent with a height profile to draw.
class ElevationProfile {
  const ElevationProfile({
    required this.climb,
    required this.descent,
    required this.lowest,
    required this.highest,
    required this.meters,
    required this.lines,
  });

  final double climb;
  final double descent;
  final double lowest;
  final double highest;

  /// Counted distance of the whole journey, the profile's width.
  final double meters;

  /// Per segment, (metres along the journey, smoothed height) points. Lines
  /// are never joined: nothing is known between segments.
  final List<List<(double, double)>> lines;
}

/// Most points kept for drawing, across all lines.
const _profilePoints = 300;

/// Replays [track] with the recorder's own rules, so the numbers match what
/// was shown while recording. Null when no fix had a usable altitude.
ElevationProfile? elevationProfile(List<List<Fix>> track, TrackPolicy policy) {
  final stats = TrackStats(policy);
  final lines = <List<(double, double)>>[];
  var points = 0;
  for (final segment in track) {
    stats.startSegment();
    final line = <(double, double)>[];
    for (final fix in segment) {
      stats.add(fix);
      if (ElevationCounter.usable(fix)) {
        line.add((stats.meters, stats.elevation.smoothed!));
      }
    }
    if (line.isNotEmpty) lines.add(line);
    points += line.length;
  }
  final climb = stats.elevation.climb;
  final descent = stats.elevation.descent;
  if (climb == null || descent == null) return null;

  final step = max(1, (points / _profilePoints).ceil());
  final thinned = [
    for (final line in lines)
      [
        for (var i = 0; i < line.length; i++)
          if (i % step == 0 || i == line.length - 1) line[i],
      ],
  ];
  final heights = [
    for (final line in thinned)
      for (final (_, height) in line) height,
  ];
  return ElevationProfile(
    climb: climb,
    descent: descent,
    lowest: heights.reduce(min),
    highest: heights.reduce(max),
    meters: stats.meters,
    lines: thinned,
  );
}
