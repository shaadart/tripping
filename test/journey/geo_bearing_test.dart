import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/geo.dart';

void main() {
  test('bearings point the way of travel, clockwise from north', () {
    expect(bearingBetween(0, 0, 1, 0), closeTo(0, 1e-9));
    expect(bearingBetween(0, 0, 0, 1), closeTo(90, 1e-9));
    expect(bearingBetween(0, 0, -1, 0), closeTo(180, 1e-9));
    expect(bearingBetween(0, 0, 0, -1), closeTo(270, 1e-9));
    // Across the antimeridian, east is still east.
    expect(bearingBetween(0, 179.9, 0, -179.9), closeTo(90, 1e-6));
  });

  test('compass points: the nearest of eight', () {
    expect(compassPoint(0), 'N');
    expect(compassPoint(22), 'N');
    expect(compassPoint(23), 'NE');
    expect(compassPoint(312), 'NW');
    expect(compassPoint(359), 'N');
    expect(compassPoint(180), 'S');
  });

  test('directions from the way of travel', () {
    expect(relativeDirection(10, 0), 'ahead');
    expect(relativeDirection(90, 0), 'right');
    expect(relativeDirection(0, 90), 'left');
    expect(relativeDirection(181, 0), 'behind');
    expect(relativeDirection(5, 320), 'ahead right');
    expect(relativeDirection(300, 10), 'left');
    expect(relativeDirection(225, 0), 'behind left');
  });
}
