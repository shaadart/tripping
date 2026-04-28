import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/places/polyline.dart';

void main() {
  test('decodes the format Google documents (precision 5)', () {
    // From Google's polyline algorithm documentation.
    expect(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5), [
      (38.5, -120.2),
      (40.7, -120.95),
      (43.252, -126.453),
    ]);
  });

  test('encoding and decoding round-trip at six decimals', () {
    const points = [
      (12.976312, 77.592911),
      (12.971601, 77.641205),
      (-33.5, -70.25),
    ];
    expect(decodePolyline(encodePolyline(points)), points);
  });

  test('an empty line is no points', () {
    expect(decodePolyline(''), isEmpty);
  });

  test('a truncated line is an error, not a guess', () {
    expect(
      () => decodePolyline('_p~iF~ps|U_', precision: 5),
      throwsFormatException,
    );
  });
}
