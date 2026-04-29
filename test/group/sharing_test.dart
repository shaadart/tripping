import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/sharing.dart';
import 'package:tripping/journey/journey.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);
const metersPerDegree = 111195.08;

Fix fixAt(int second, double north) => Fix(
  time: t0.add(Duration(seconds: second)),
  latitude: 11.4 + north / metersPerDegree,
  longitude: 76.7,
  accuracy: 4.6,
);

Shared shared(JourneyPhase phase, Fix? fix, {JourneyMode? mode}) => Shared(
  name: 'Asha',
  phase: phase,
  mode: mode ?? JourneyMode.road,
  fix: fix,
);

void main() {
  test('a message round-trips to about a metre and stays small', () {
    final message = Shared(
      name: 'x' * 40,
      phase: JourneyPhase.paused,
      mode: JourneyMode.expedition,
      fix: fixAt(0, 123.456),
    ).toMessage();
    expect(utf8.encode(jsonEncode(message)).length, lessThan(200));
    final back = Shared.fromMessage(
      jsonDecode(jsonEncode(message)) as Map<String, Object?>,
    )!;
    expect(
      (back.phase, back.mode),
      (JourneyPhase.paused, JourneyMode.expedition),
    );
    expect(back.fix!.latitude, closeTo(fixAt(0, 123.456).latitude, 1e-5));
    expect(back.fix!.accuracy, 5);
    expect(back.fix!.time, t0);
  });

  test('a message without a position says so; nonsense is refused', () {
    final message = shared(JourneyPhase.recording, null).toMessage();
    expect(message.containsKey('p'), isFalse);
    expect(Shared.fromMessage(message)!.fix, isNull);
    expect(Shared.fromMessage({'n': 'A', 's': 'x', 'm': 'r'}), isNull);
    expect(
      Shared.fromMessage({
        'n': 'A',
        's': 'r',
        'm': 'r',
        'p': [95, 0, 1, 1],
      })!.fix,
      isNull,
      reason: 'no such latitude',
    );
  });

  group('road: every 10 s or 100 m, never within 2.5 s', () {
    const policy = SharePolicy.road;
    final told = shared(JourneyPhase.recording, fixAt(0, 0));

    test('the first is always told', () {
      expect(policy.due(told, null, t0, t0), isTrue);
    });

    test('time', () {
      final now = shared(JourneyPhase.recording, fixAt(9, 10));
      expect(
        policy.due(now, told, t0, t0.add(const Duration(seconds: 9))),
        isFalse,
      );
      expect(
        policy.due(now, told, t0, t0.add(const Duration(seconds: 10))),
        isTrue,
      );
    });

    test('distance', () {
      final far = shared(JourneyPhase.recording, fixAt(4, 105));
      expect(
        policy.due(far, told, t0, t0.add(const Duration(seconds: 4))),
        isTrue,
      );
      expect(
        policy.due(far, told, t0, t0.add(const Duration(seconds: 2))),
        isFalse,
        reason: 'the relay refuses writes closer than 2 s',
      );
    });

    test('a pause or an end goes at once', () {
      final paused = shared(JourneyPhase.paused, fixAt(3, 0));
      expect(
        policy.due(paused, told, t0, t0.add(const Duration(seconds: 3))),
        isTrue,
      );
    });
  });

  test('expedition: every 30 s or 50 m', () {
    const policy = SharePolicy.expedition;
    final told = shared(
      JourneyPhase.recording,
      fixAt(0, 0),
      mode: JourneyMode.expedition,
    );
    final near = shared(
      JourneyPhase.recording,
      fixAt(20, 40),
      mode: JourneyMode.expedition,
    );
    final far = shared(
      JourneyPhase.recording,
      fixAt(20, 55),
      mode: JourneyMode.expedition,
    );
    final at = t0.add(const Duration(seconds: 20));
    expect(policy.due(near, told, t0, at), isFalse);
    expect(policy.due(far, told, t0, at), isTrue);
    expect(
      policy.due(near, told, t0, t0.add(const Duration(seconds: 30))),
      isTrue,
    );
  });

  test('freshness by age and mode', () {
    expect(
      freshnessOf(const Duration(seconds: 20), JourneyMode.road),
      Freshness.live,
    );
    expect(
      freshnessOf(const Duration(seconds: 40), JourneyMode.road),
      Freshness.aging,
    );
    expect(
      freshnessOf(const Duration(seconds: 60), JourneyMode.expedition),
      Freshness.live,
    );
    expect(
      freshnessOf(const Duration(minutes: 6), JourneyMode.expedition),
      Freshness.stale,
    );
  });

  test('distance and direction in words', () {
    expect(distanceAndDirection(fixAt(0, 0), fixAt(0, 10)), 'here');
    expect(distanceAndDirection(fixAt(0, 0), fixAt(0, 345)), '350 m N');
    expect(distanceAndDirection(fixAt(0, 0), fixAt(0, -1234)), '1.2 km S');
    expect(distanceAndDirection(fixAt(0, 0), fixAt(0, 15500)), '16 km N');
    expect(distanceAndDirection(fixAt(0, 0), fixAt(0, 999.8)), '1.0 km N');
  });
}
