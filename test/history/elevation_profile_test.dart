import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/history/elevation_profile.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/track_policy.dart';
import 'package:tripping/recording/track_stats.dart';

import '../recording/elevation_test.dart' show climbTrace;
import '../support/fakes.dart';

void main() {
  final policy = TrackPolicy.of(JourneyMode.expedition);

  test('no usable altitude, no profile', () {
    expect(
      elevationProfile([
        [walkFix(0), walkFix(1)],
      ], policy),
      isNull,
    );
  });

  test('numbers match the live count; one thin line per segment', () {
    final up = climbTrace((s) => 2000 + 200 * s / 3600, seed: 1);
    final later = [
      for (final fix in climbTrace((_) => 2300, seed: 2, seconds: 600))
        Fix(
          time: fix.time.add(const Duration(hours: 2)),
          latitude: fix.latitude + 0.1,
          longitude: fix.longitude,
          accuracy: fix.accuracy,
          altitude: fix.altitude,
          altitudeAccuracy: fix.altitudeAccuracy,
        ),
    ];
    final track = [up, <Fix>[], later];
    final profile = elevationProfile(track, policy)!;
    final stats = TrackStats.replay(policy, track);

    expect(profile.climb, stats.elevation.climb);
    expect(profile.descent, stats.elevation.descent);
    expect(profile.meters, stats.meters);
    expect(profile.lines, hasLength(2));
    final points = profile.lines.fold(0, (sum, line) => sum + line.length);
    expect(points, lessThanOrEqualTo(310));
    expect(profile.lowest, lessThan(2050));
    expect(profile.highest, greaterThan(2250));
    // Distance only grows along the journey.
    final xs = [
      for (final line in profile.lines)
        for (final (x, _) in line) x,
    ];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThanOrEqualTo(xs[i - 1]));
    }
  });
}
