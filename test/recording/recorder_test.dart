import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/location_source.dart';
import 'package:tripping/recording/recorder.dart';
import 'package:tripping/recording/track_policy.dart';
import 'package:tripping/recording/track_stats.dart';

import '../support/fakes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FlakyStore store;
  late FakeLocation location;
  late DateTime now;
  late Recorder recorder;

  Future<Recorder> openRecorder() =>
      Recorder.open(store, location, clock: () => now);

  Future<void> walk(int from, int to, {double startNorth = 0}) async {
    for (var second = from; second <= to; second++) {
      location.emit(walkFix(second, startNorth: startNorth));
    }
    await recorder.settled();
  }

  setUp(() async {
    store = FlakyStore(NativeDatabase.memory());
    location = FakeLocation();
    now = t0;
    recorder = await openRecorder();
  });

  tearDown(() async {
    await recorder.close();
    await store.close();
  });

  test('opens idle when no journey is active', () {
    expect(recorder.state, isA<Idle>());
  });

  test(
    'records, pauses, resumes and ends with correct segments and stats',
    () async {
      expect(
        await recorder.start(JourneyMode.expedition),
        LocationAccess.granted,
      );
      expect(recorder.state, isA<Recording>());
      expect((recorder.state as Recording).latestFix, isNull);

      await walk(0, 100);
      now = t0.add(const Duration(seconds: 101));
      await recorder.pause();
      expect(recorder.state, isA<Paused>());
      expect(location.listening, isFalse);

      // Walked on 500 m with the app paused: that stretch is never counted.
      now = t0.add(const Duration(seconds: 500));
      await recorder.resume();
      await walk(500, 600, startNorth: 500);
      now = t0.add(const Duration(seconds: 601));
      final last = await recorder.end();

      expect(recorder.state, isA<Idle>());
      final journey = (await store.allJourneys()).single;
      expect(journey.status, JourneyStatus.ended);
      final segments = await store.segmentsOf(journey.id);
      expect(segments.map((s) => s.endReason), [
        SegmentEnd.paused,
        SegmentEnd.ended,
      ]);

      final track = await store.track(journey.id);
      expect(track.map((s) => s.length), [101, 101]);
      final replayed = TrackStats.replay(TrackPolicy.expedition, track);
      expect(last!.meters, replayed.meters);
      expect(last.movingTime, replayed.movingTime);
      // Two walks of 150 m, each trailing by at most one gate (never more
      // than the truth, give or take rounding).
      expect(last.meters, inInclusiveRange(276, 300.001));
      expect(last.elapsedAt(now), const Duration(seconds: 202));
    },
  );

  test('a double start creates one journey', () async {
    await Future.wait([
      recorder.start(JourneyMode.road),
      recorder.start(JourneyMode.road),
    ]);
    await recorder.start(JourneyMode.expedition);

    expect(await store.allJourneys(), hasLength(1));
    expect(location.requests, 1);
  });

  test('without location access, start says why and creates nothing', () async {
    location.access = LocationAccess.deniedForever;

    expect(
      await recorder.start(JourneyMode.road),
      LocationAccess.deniedForever,
    );

    expect(recorder.state, isA<Idle>());
    expect(await store.allJourneys(), isEmpty);
    expect(location.listening, isFalse);
  });

  test(
    'losing location keeps recording and says so until fixes return',
    () async {
      await recorder.start(JourneyMode.road);
      await walk(0, 10);

      location.lose(LocationAccess.serviceOff);
      await recorder.settled();

      final lost = recorder.state as Recording;
      expect(lost.locationProblem, isA<LocationUnavailable>());
      expect((await store.activeJourney())?.status, JourneyStatus.recording);

      await walk(60, 61);
      expect((recorder.state as Recording).locationProblem, isNull);
    },
  );

  test('a fix that cannot be saved is reported and never counted', () async {
    await recorder.start(JourneyMode.expedition);
    await walk(0, 20);
    final before = (recorder.state as Recording).progress;

    store.failAppends = true;
    await walk(21, 40);

    final failing = recorder.state as Recording;
    expect(failing.saveError, isA<FileSystemException>());
    expect(failing.progress.meters, before.meters);
    expect(failing.progress.lastFix, before.lastFix);

    store.failAppends = false;
    await walk(41, 60);
    final recovered = recorder.state as Recording;
    expect(recovered.saveError, isNull);
    expect(recovered.progress.meters, greaterThan(before.meters));
  });

  test('an inaccurate fix moves the position but not the track', () async {
    await recorder.start(JourneyMode.road);
    await walk(0, 5);
    final vague = Fix(
      time: t0.add(const Duration(seconds: 6)),
      latitude: 32.001,
      longitude: 77,
      accuracy: 400,
    );

    location.emit(vague);
    await recorder.settled();

    final state = recorder.state as Recording;
    expect(state.latestFix, vague);
    expect(state.progress.lastFix, walkFix(5));
  });

  group('after the process dies', () {
    test('reopening reports the interruption at the last saved fix', () async {
      await recorder.start(JourneyMode.expedition);
      await walk(0, 120);
      final before = (recorder.state as Recording).progress;
      await recorder.close(); // the process dies: nothing is written

      now = t0.add(const Duration(hours: 2));
      recorder = await openRecorder();

      final interrupted = recorder.state as Interrupted;
      expect(interrupted.stoppedAt, walkFix(120).time);
      expect(interrupted.progress.meters, before.meters);
      expect(interrupted.progress.elapsedAt(now), const Duration(seconds: 120));
    });

    test(
      'resuming continues in a new segment without bridging the gap',
      () async {
        await recorder.start(JourneyMode.expedition);
        await walk(0, 100);
        final before = (recorder.state as Recording).progress.meters;
        await recorder.close();
        recorder = await openRecorder();

        now = t0.add(const Duration(hours: 1));
        await recorder.resume();
        await walk(3600, 3700, startNorth: 2000);

        final journey = (await store.activeJourney())!;
        final reasons = (await store.segmentsOf(
          journey.id,
        )).map((s) => s.endReason);
        expect(reasons, [SegmentEnd.interrupted, null]);
        final meters = (recorder.state as Recording).progress.meters;
        expect(meters - before, inInclusiveRange(138, 150.001));
      },
    );

    test('older fixes are never stored after a restart', () async {
      await recorder.start(JourneyMode.road);
      await walk(0, 30);
      await recorder.close();
      recorder = await openRecorder();
      await recorder.resume();

      location.emit(walkFix(10));
      await recorder.settled();

      final journey = (await store.activeJourney())!;
      expect((await store.track(journey.id)).last, isEmpty);
    });

    test('a pause made by the user stays a pause', () async {
      await recorder.start(JourneyMode.road);
      await walk(0, 10);
      await recorder.pause();
      await recorder.close();

      recorder = await openRecorder();

      expect(recorder.state, isA<Paused>());
    });
  });

  test('resuming without location access stays paused', () async {
    await recorder.start(JourneyMode.road);
    await recorder.pause();
    location.access = LocationAccess.serviceOff;

    expect(await recorder.resume(), LocationAccess.serviceOff);
    expect(recorder.state, isA<Paused>());
  });

  test('a clock set back never ends a segment before it began', () async {
    await recorder.start(JourneyMode.road);

    now = t0.subtract(const Duration(hours: 1));
    await recorder.pause();

    final journey = (await store.activeJourney())!;
    final segment = (await store.segmentsOf(journey.id)).single;
    expect(segment.endedAt!.isBefore(segment.startedAt), isFalse);
    expect((recorder.state as Paused).progress.closedTime, Duration.zero);
  });

  test('only one recorder can own a store at a time', () async {
    expect(openRecorder, throwsStateError);

    await recorder.close();
    recorder = await openRecorder();
    expect(recorder.state, isA<Idle>());
  });

  test(
    'if storage goes away, commands fail loudly and state stays true',
    () async {
      await recorder.start(JourneyMode.road);
      await walk(0, 5);
      await store.close();

      await expectLater(recorder.pause(), throwsA(anything));
      expect(recorder.state, isA<Recording>());

      await walk(6, 7);
      expect((recorder.state as Recording).saveError, isNotNull);
    },
  );
}
