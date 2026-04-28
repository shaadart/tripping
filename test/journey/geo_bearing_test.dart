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
}
