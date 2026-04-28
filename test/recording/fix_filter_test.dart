import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/fix_filter.dart';
import 'package:tripping/recording/track_policy.dart';

final t0 = DateTime.utc(2026, 10, 27, 6);

/// About 111 m per 0.001° of latitude.
Fix fix(
  int second, {
  double north = 0,
  double? accuracy = 5,
  double latitude = 32.2432,
  double longitude = 77.1892,
}) => Fix(
  time: t0.add(Duration(seconds: second)),
  latitude: latitude + north,
  longitude: longitude,
  accuracy: accuracy,
);

void main() {
  late FixFilter filter;
  setUp(() => filter = FixFilter(TrackPolicy.road));

  test('accepts the first fix and plausible successors', () {
    expect(filter.judge(fix(0)), FixVerdict.accepted);
    expect(filter.judge(fix(1, north: 0.0002)), FixVerdict.accepted);
  });

  test('refuses duplicates and fixes older than one already judged', () {
    filter.judge(fix(5));

    expect(filter.judge(fix(5)), FixVerdict.stale);
    expect(filter.judge(fix(3)), FixVerdict.stale);
    expect(filter.judge(fix(6)), FixVerdict.accepted);
  });

  test('refuses positions that cannot be real', () {
    expect(filter.judge(fix(1, latitude: double.nan)), FixVerdict.invalid);
    expect(filter.judge(fix(2, latitude: 91)), FixVerdict.invalid);
    expect(filter.judge(fix(3, longitude: 181)), FixVerdict.invalid);
    expect(filter.judge(fix(4, latitude: 0, longitude: 0)), FixVerdict.invalid);
    expect(filter.judge(fix(5, accuracy: -1)), FixVerdict.invalid);
  });

  test('leaves out fixes less accurate than the mode allows', () {
    expect(filter.judge(fix(1, accuracy: 51)), FixVerdict.inaccurate);
    expect(filter.judge(fix(2, accuracy: 50)), FixVerdict.accepted);
    expect(filter.judge(fix(3, accuracy: null)), FixVerdict.accepted);
  });

  test('holds back a jump until consistent fixes confirm it', () {
    filter.judge(fix(0));
    const far = 0.1; // about 11 km north

    expect(filter.judge(fix(1, north: far)), FixVerdict.implausible);
    expect(filter.judge(fix(2, north: far)), FixVerdict.implausible);
    expect(filter.judge(fix(3, north: far)), FixVerdict.relocated);
    expect(filter.judge(fix(4, north: far)), FixVerdict.accepted);
  });

  test('suspects that disagree with each other confirm nothing', () {
    filter.judge(fix(0));

    expect(filter.judge(fix(1, north: 0.1)), FixVerdict.implausible);
    expect(filter.judge(fix(2, north: -0.1)), FixVerdict.implausible);
    expect(filter.judge(fix(3, north: 0.1)), FixVerdict.implausible);
    expect(filter.judge(fix(4)), FixVerdict.accepted);
  });

  test('a new segment may start anywhere but not in the past', () {
    filter.judge(fix(10));
    filter.startSegment();

    expect(filter.judge(fix(9, north: 1)), FixVerdict.stale);
    expect(filter.judge(fix(3600, north: 1)), FixVerdict.accepted);
  });
}
