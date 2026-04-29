import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/convoy.dart';
import 'package:tripping/journey/journey.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);
const metersPerDegree = 111195.08;

(double, double) at(double north, [double east = 0]) =>
    (12.9 + north / metersPerDegree, 77.6 + east / (metersPerDegree * 0.9748));

Fix fix(double north, [double east = 0, int second = 0]) {
  final (lat, lon) = at(north, east);
  return Fix(
    time: t0.add(Duration(seconds: second)),
    latitude: lat,
    longitude: lon,
  );
}

void main() {
  // A road 5 km north, then 3 km east.
  final convoy = Convoy([at(0), at(5000), at(5000, 3000)]);
  final me = fix(1000);

  test('ahead and behind are measured along the road', () {
    expect(convoy.gapText(me, fix(2200)), '1.2 km ahead');
    expect(convoy.gapText(me, fix(400, 30)), '600 m behind');
    expect(convoy.gapText(me, fix(1020)), 'alongside');
    // Round the corner: 4 km + 1.5 km along, not 4.3 km as the crow flies.
    expect(convoy.gapText(me, fix(5000, 1500)), '5.5 km ahead');
  });

  test('off the road, no "ahead" or "behind"', () {
    expect(convoy.gapText(me, fix(2000, 500)), isNull);
    expect(convoy.gapText(fix(1000, 400), fix(2000)), isNull);
    expect(Convoy(const []).gapText(me, fix(2000)), isNull);
  });

  test('a convoy in order: the leader, the middle, the last', () {
    final cars = {'lead': fix(3000), 'mid': fix(1500), 'tail': fix(200)};
    final order = cars.entries.toList()
      ..sort(
        (a, b) => convoy.alongOf(b.value)!.compareTo(convoy.alongOf(a.value)!),
      );
    expect([for (final e in order) e.key], ['lead', 'mid', 'tail']);
  });

  group('stopped', () {
    test('after more than 2 minutes within 30 m', () {
      final still = Stillness();
      expect(still.update(fix(0, 0, 0), t0), isNull);
      expect(
        still.update(fix(10, 5, 60), t0.add(const Duration(seconds: 60))),
        isNull,
      );
      expect(
        still.update(fix(5, 0, 120), t0.add(const Duration(seconds: 120))),
        isNull,
      );
      expect(
        still.update(fix(8, 3, 150), t0.add(const Duration(seconds: 150))),
        t0,
      );
    });

    test('moving on starts over', () {
      final still = Stillness();
      still.update(fix(0), t0);
      expect(
        still.update(fix(0, 0, 180), t0.add(const Duration(minutes: 3))),
        t0,
      );
      final moved = t0.add(const Duration(minutes: 4));
      expect(still.update(fix(200, 0, 240), moved), isNull);
      expect(
        still.update(fix(205, 0, 300), t0.add(const Duration(minutes: 5))),
        isNull,
      );
    });

    test('creeping in traffic is not stopped', () {
      final still = Stillness();
      for (var s = 0; s <= 300; s += 30) {
        expect(
          still.update(fix(s * 0.5), t0.add(Duration(seconds: s))),
          isNull,
          reason: 'moving 15 m every 30 s',
        );
      }
    });
  });
}
