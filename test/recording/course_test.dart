import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/course.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);
const metersPerDegree = 111195.08;

Fix at(
  int second,
  double north,
  double east, {
  double accuracy = 5,
  double? speed,
  double? heading,
}) => Fix(
  time: t0.add(Duration(seconds: second)),
  latitude: 32 + north / metersPerDegree,
  longitude: 77 + east / (metersPerDegree * 0.848048),
  accuracy: accuracy,
  speed: speed,
  heading: heading,
);

void main() {
  test('the GPS heading, when moving', () {
    expect(Course().update(at(0, 0, 0, speed: 1.4, heading: 80)), 80);
  });

  test('a heading while standing is not trusted', () {
    expect(Course().update(at(0, 0, 0, speed: 0.1, heading: 80)), isNull);
  });

  test('without a heading, the way the last 25 m went', () {
    final course = Course();
    for (var s = 0; s < 17; s++) {
      expect(course.update(at(s, 1.4 * s, 0)), isNull, reason: '$s s');
    }
    // 25.2 m north after 18 s.
    expect(course.update(at(18, 25.2, 0)), closeTo(0, 0.5));
    for (var s = 1; s <= 20; s++) {
      course.update(at(18 + s, 25.2, 1.4 * s));
    }
    expect(course.update(at(39, 25.2, 29.4)), closeTo(90, 1));
  });

  test('vague fixes need further to go: noise is not movement', () {
    final course = Course();
    course.update(at(0, 0, 0, accuracy: 20));
    // 40 m of wobble at ±20 m: under 3 × 20 = 60 m.
    expect(course.update(at(5, 40, 0, accuracy: 20)), isNull);
    expect(course.update(at(10, 65, 0, accuracy: 20)), closeTo(0, 0.5));
  });

  test('standing for 30 s forgets the direction', () {
    final course = Course();
    course.update(at(0, 0, 0, speed: 1.4, heading: 45));
    expect(course.update(at(20, 0, 0)), 45);
    expect(course.update(at(31, 0, 0)), isNull);
  });
}
