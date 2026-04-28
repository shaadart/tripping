import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/routing/route_progress.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);
const origin = (12.97, 77.59);
const metersPerDegree = 111195.08;

/// The point [east] and [north] metres from [origin].
(double, double) at(double east, double north) => (
  origin.$1 + north / metersPerDegree,
  origin.$2 + east / (metersPerDegree * cos(origin.$1 * pi / 180)),
);

Fix fixAt(int second, double east, double north, {double accuracy = 5}) {
  final (lat, lon) = at(east, north);
  return Fix(
    time: t0.add(Duration(seconds: second)),
    latitude: lat,
    longitude: lon,
    accuracy: accuracy,
  );
}

/// 1 km east, then 1 km north: 2 km of road, which the service called
/// 2.1 km and 300 s.
RouteFollower ell() => RouteFollower(
  points: [at(0, 0), at(1000, 0), at(1000, 1000)],
  kind: RouteKind.road,
  meters: 2100,
  seconds: 300,
  destination: at(1000, 1000),
);

void main() {
  test('on the road, what is left shrinks steadily and stays on it', () {
    final follower = ell();
    final random = Random(1);
    var previous = double.infinity;
    for (var s = 0; s <= 190; s++) {
      final d = s * 10.0;
      // ±10 m of GPS scatter across the road.
      final across = (random.nextDouble() - 0.5) * 20;
      final fix = d <= 1000
          ? fixAt(s, d, across)
          : fixAt(s, 1000 + across, d - 1000);
      final progress = follower.update(fix);
      expect(progress.offRoute, isFalse, reason: 'second $s');
      expect(progress.metersLeft, lessThanOrEqualTo(previous + 15));
      previous = progress.metersLeft;
      if (s == 100) {
        expect(progress.metersLeft, closeTo(1050, 15));
        expect(progress.secondsLeft, closeTo(150, 3));
      }
    }
  });

  test('a detour is off the road after 20 s away, not before', () {
    final follower = ell();
    for (var s = 0; s <= 50; s++) {
      follower.update(fixAt(s, s * 10.0, 0));
    }
    // Turns south off the road at 500 m, 5 m/s: 50 m away after 10 s.
    RouteProgress? progress;
    for (var s = 1; s <= 40; s++) {
      progress = follower.update(fixAt(50 + s, 500, -5.0 * s));
      final awayFor = s - 10;
      expect(
        progress.offRoute,
        awayFor >= 20,
        reason: '$s s after the turn, ${5 * s} m away',
      );
    }
    // Off the road: a straight line, and no estimate pretending otherwise.
    final straight = sqrt(500 * 500 + 1200 * 1200);
    expect(progress!.metersLeft, closeTo(straight, 5));
    expect(progress.secondsLeft, isNull);

    // Back on the road: on it again at once.
    progress = follower.update(fixAt(100, 520, 3));
    expect(progress.offRoute, isFalse);
    expect(progress.metersLeft, closeTo(2100 * 1480 / 2000, 15));
  });

  test('starting off the road is not leaving it; going further off is', () {
    // A car park 120 m south of where the road begins.
    final follower = ell();
    for (var s = 0; s <= 60; s++) {
      expect(follower.update(fixAt(s, 3, -120)).offRoute, isFalse);
    }
    // Driving away from the road: 50 m further off, then 20 s.
    for (var s = 1; s <= 40; s++) {
      final progress = follower.update(fixAt(60 + s, 3, -120 - 5.0 * s));
      expect(progress.offRoute, s >= 30, reason: '${5 * s} m further off');
    }
  });

  test('once on the road, the usual 50 m applies again', () {
    final follower = ell();
    follower.update(fixAt(0, 0, -120));
    for (var s = 1; s <= 12; s++) {
      follower.update(fixAt(s, 0, -120 + 10.0 * s));
    }
    // Joined; now 60 m off for 25 s.
    for (var s = 13; s <= 40; s++) {
      follower.update(fixAt(s, 300, -60));
    }
    expect(follower.update(fixAt(41, 300, -60)).offRoute, isTrue);
  });

  test('one wild fix is not a detour and does not move what is left', () {
    final follower = ell();
    late RouteProgress before;
    for (var s = 0; s <= 40; s++) {
      before = follower.update(fixAt(s, s * 10.0, 0));
    }
    final jump = follower.update(fixAt(41, 410, 300));
    expect(jump.offRoute, isFalse);
    expect(jump.metersLeft, closeTo(before.metersLeft, 1));
    expect(follower.update(fixAt(42, 420, 0)).offRoute, isFalse);
  });

  test('vague fixes far away never say off the road', () {
    final follower = ell();
    follower.update(fixAt(0, 0, 0));
    for (var s = 1; s <= 60; s++) {
      final progress = follower.update(fixAt(s, 200, 150, accuracy: 120));
      expect(progress.offRoute, isFalse);
    }
  });

  test('a road out and back along itself is followed, not jumped across', () {
    // Out 1 km east, back 700 m 10 m further north, then 490 m north:
    // 2.2 km.
    final follower = RouteFollower(
      points: [at(0, 0), at(1000, 0), at(1000, 10), at(300, 10), at(300, 500)],
      kind: RouteKind.road,
      meters: 2200,
      seconds: 220,
      destination: at(300, 500),
    );
    for (var s = 0; s <= 90; s++) {
      follower.update(fixAt(s, s * 10.0, 0));
    }
    // Out: 900 m along, not 1,110 on the way back.
    expect(follower.update(fixAt(91, 900, 7)).metersLeft, closeTo(1300, 15));
    for (var s = 92; s <= 100; s++) {
      follower.update(fixAt(s, (s - 1) * 10.0, 2));
    }
    for (var s = 0; s <= 10; s++) {
      follower.update(fixAt(101 + s, 1000 - s * 10.0, 9));
    }
    // Back: 1,110 m along, though the outbound road is as near.
    expect(follower.update(fixAt(112, 900, 3)).metersLeft, closeTo(1090, 15));
  });

  test('turning back along the road gives the distance back', () {
    final follower = ell();
    for (var s = 0; s <= 60; s++) {
      follower.update(fixAt(s, s * 10.0, 0));
    }
    late RouteProgress progress;
    for (var s = 1; s <= 30; s++) {
      progress = follower.update(fixAt(60 + s, 600 - s * 10.0, 0));
      expect(progress.offRoute, isFalse);
    }
    expect(progress.metersLeft, closeTo(2100 * 1700 / 2000, 15));
  });

  test('within 50 m of the destination is there, and stays there', () {
    final follower = ell();
    expect(follower.update(fixAt(0, 1000, 900)).arrived, isFalse);
    final there = follower.update(fixAt(1, 1000, 960));
    expect(there.arrived, isTrue);
    expect(there.metersLeft, 0);
    // Driving on past it, or into the car park, does not undo arriving.
    expect(follower.update(fixAt(2, 1100, 1100)).arrived, isTrue);
  });

  test('a straight line says the straight distance and is never left', () {
    final follower = RouteFollower(
      points: [at(0, 0), at(1000, 1000)],
      kind: RouteKind.straight,
      meters: 1414,
      seconds: null,
      destination: at(1000, 1000),
    );
    for (var s = 0; s <= 60; s++) {
      final progress = follower.update(fixAt(s, -s * 10.0, 0));
      expect(progress.offRoute, isFalse);
      expect(progress.secondsLeft, isNull);
    }
    final progress = follower.update(fixAt(61, 0, 0));
    expect(progress.metersLeft, closeTo(1414, 3));
  });
}
