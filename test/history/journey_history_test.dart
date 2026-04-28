import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/history/journey_history.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/recording/track_policy.dart';
import 'package:tripping/recording/track_stats.dart';

import '../support/fakes.dart';
import '../support/traces.dart';

void main() {
  late JourneyStore store;
  late JourneyHistory history;

  setUp(() {
    store = JourneyStore(NativeDatabase.memory());
    history = JourneyHistory(store);
  });
  tearDown(() => store.close());

  /// A walk of two segments: 2 min, a 1 min pause, then 1 min more.
  Future<JourneyRow> recordWalk() async {
    final journey = await store.startJourney(JourneyMode.expedition, at: t0);
    for (var s = 0; s < 120; s++) {
      await store.append(journey.id, walkFix(s));
    }
    await store.pause(journey.id, at: t0.add(const Duration(seconds: 120)));
    await store.resume(journey.id, at: t0.add(const Duration(seconds: 180)));
    for (var s = 180; s < 240; s++) {
      await store.append(journey.id, walkFix(s));
    }
    await store.end(journey.id, at: t0.add(const Duration(seconds: 240)));
    return journey;
  }

  test('an ended journey is summarised from its track, once', () async {
    final journey = await recordWalk();
    final track = await store.track(journey.id);
    final expected = TrackStats.replay(
      TrackPolicy.of(JourneyMode.expedition),
      track,
    );

    final past = (await history.load()).single;
    expect(past.journey.id, journey.id);
    expect(past.meters, expected.meters);
    expect(past.movingTime, expected.movingTime);
    expect(past.recordedTime, const Duration(minutes: 3));
    expect(past.outline, hasLength(2));
    // A straight walk needs only its ends.
    expect(past.outline.first, hasLength(2));

    // Saved: a second load reads the cache instead of the track.
    await store.saveSummary(
      journey.id,
      version: summaryVersion,
      meters: 12345,
      movingTime: Duration.zero,
      recordedTime: Duration.zero,
      outline: '[]',
    );
    expect((await history.load()).single.meters, 12345);
  });

  test('a summary from older rules is derived again', () async {
    final journey = await recordWalk();
    await store.saveSummary(
      journey.id,
      version: summaryVersion - 1,
      meters: 12345,
      movingTime: Duration.zero,
      recordedTime: Duration.zero,
      outline: '[]',
    );
    final past = (await history.load()).single;
    expect(past.meters, isNot(12345));
    expect(past.outline, hasLength(2));
  });

  test('only ended journeys are listed, newest first', () async {
    await recordWalk();
    final later = await store.startJourney(
      JourneyMode.road,
      at: t0.add(const Duration(hours: 1)),
    );
    await store.end(later.id, at: t0.add(const Duration(hours: 2)));
    await store.startJourney(
      JourneyMode.expedition,
      at: t0.add(const Duration(hours: 3)),
    );

    final listed = await history.load();
    expect(listed.map((p) => p.journey.mode), [
      JourneyMode.road,
      JourneyMode.expedition,
    ]);
    expect(listed.first.meters, 0);
    expect(listed.first.outline, isEmpty);
  });

  test(
    'the drawn track keeps segments apart and drops invisible detail',
    () async {
      final journey = await recordWalk();
      final track = await history.trackOf(journey.id);
      expect(track, hasLength(2));
      expect(track.first, [walkFix(0), walkFix(119)]);
      expect(track.last, [walkFix(180), walkFix(239)]);
    },
  );

  test('GPX holds every recorded fix, in its segments', () async {
    await recordWalk();
    final past = (await history.load()).single;
    final out = await history.gpxOf(past, name: 'Walk');
    expect('<trkseg>'.allMatches(out), hasLength(2));
    expect('<trkpt '.allMatches(out), hasLength(180));
  });

  test('delete removes the journey', () async {
    final journey = await recordWalk();
    await history.delete(journey.id);
    expect(await history.load(), isEmpty);
  });

  group('outline', () {
    test('stays small for a long journey', () {
      final trace = TraceBuilder(seed: 5, accuracy: 5);
      for (var hour = 0; hour < 12; hour++) {
        trace.move(
          duration: const Duration(hours: 1),
          speed: 15,
          heading: hour * 61.0 % 360,
        );
      }
      final outline = outlineOf([trace.fixes]);
      final points = outline.single.length;
      expect(points, inInclusiveRange(10, 120));
    });

    test('survives a round trip through JSON to about a metre', () {
      final outline = outlineOf([
        [walkFix(0), walkFix(100)],
        [walkFix(200), walkFix(300)],
      ]);
      final decoded = decodeOutline(encodeOutline(outline));
      expect(decoded, hasLength(2));
      for (var i = 0; i < 2; i++) {
        for (var j = 0; j < 2; j++) {
          expect(decoded[i][j].latitude, closeTo(outline[i][j].latitude, 1e-5));
          expect(
            decoded[i][j].longitude,
            closeTo(outline[i][j].longitude, 1e-5),
          );
        }
      }
    });
  });
}
