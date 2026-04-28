import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/format.dart';

void main() {
  test('distances lose decimals as they grow', () {
    expect(kilometres(0), '0.00 km');
    expect(kilometres(256), '0.26 km');
    expect(kilometres(9994), '9.99 km');
    expect(kilometres(12345), '12.3 km');
    expect(kilometres(1211600), '1212 km');
  });

  test('clock time counts hours past a day', () {
    expect(
      clockTime(const Duration(hours: 25, minutes: 3, seconds: 9)),
      '25:03:09',
    );
  });
}
