import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

final t0 = DateTime.utc(2026, 10, 27, 6, 30);

Fix fixAt(int second, {double latitude = 32.2432}) => Fix(
  time: t0.add(Duration(seconds: second)),
  latitude: latitude,
  longitude: 77.1892,
  accuracy: 4.5,
);

void main() {
  // The kill test deliberately opens a second, separate database file.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late JourneyStore store;

  setUp(() => store = JourneyStore(NativeDatabase.memory()));
  tearDown(() => store.close());

  test('starting opens a recording journey with one open segment', () async {
    final journey = await store.startJourney(JourneyMode.expedition, at: t0);

    expect(journey.status, JourneyStatus.recording);
    expect(journey.mode, JourneyMode.expedition);
    expect(journey.uuid, hasLength(36));
    expect((await store.activeJourney())?.id, journey.id);
    final segments = await store.segmentsOf(journey.id);
    expect(segments.single.startedAt, t0);
    expect(segments.single.endedAt, isNull);
  });

  group('one active journey', () {
    test('a second start is refused while one is active', () async {
      await store.startJourney(JourneyMode.road, at: t0);

      expect(
        () => store.startJourney(JourneyMode.expedition, at: t0),
        throwsStateError,
      );
    });

    test('the database refuses a second active row on its own', () async {
      final first = await store.startJourney(JourneyMode.road, at: t0);
      await store.pause(first.id, at: t0);

      final secondActive = store
          .into(store.journeys)
          .insert(
            JourneysCompanion.insert(
              uuid: 'not-via-the-api',
              mode: JourneyMode.road,
              status: JourneyStatus.recording,
              createdAt: t0,
            ),
          );

      await expectLater(secondActive, throwsA(isA<Exception>()));
    });

    test('a new journey can start once the previous one ends', () async {
      final first = await store.startJourney(JourneyMode.road, at: t0);
      await store.end(first.id, at: t0.add(const Duration(hours: 1)));

      final second = await store.startJourney(
        JourneyMode.expedition,
        at: t0.add(const Duration(hours: 2)),
      );

      expect((await store.activeJourney())?.id, second.id);
      expect(await store.allJourneys(), [
        isA<JourneyRow>().having((j) => j.id, 'id', second.id),
        isA<JourneyRow>().having((j) => j.id, 'id', first.id),
      ]);
    });
  });

  group('append', () {
    test(
      'stores fixes ordered by fix time, whatever the arrival order',
      () async {
        final journey = await store.startJourney(JourneyMode.road, at: t0);

        expect(await store.append(journey.id, fixAt(2)), AppendResult.stored);
        expect(await store.append(journey.id, fixAt(1)), AppendResult.stored);

        expect(await store.track(journey.id), [
          [fixAt(1), fixAt(2)],
        ]);
      },
    );

    test('re-delivering a fix is a harmless no-op', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);
      await store.append(journey.id, fixAt(1));

      final again = await store.append(journey.id, fixAt(1, latitude: 0));

      expect(again, AppendResult.duplicate);
      expect(await store.track(journey.id), [
        [fixAt(1)],
      ]);
    });

    test(
      'is refused while paused, after ending, and for unknown journeys',
      () async {
        final journey = await store.startJourney(JourneyMode.road, at: t0);
        await store.pause(journey.id, at: t0);
        expect(
          await store.append(journey.id, fixAt(1)),
          AppendResult.notRecording,
        );

        await store.end(journey.id, at: t0);
        expect(
          await store.append(journey.id, fixAt(2)),
          AppendResult.notRecording,
        );
        expect(await store.append(9999, fixAt(3)), AppendResult.notRecording);
        expect(await store.track(journey.id), [<Fix>[]]);
      },
    );

    test('keeps millisecond precision and UTC', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);
      final precise = Fix(
        time: t0.add(const Duration(milliseconds: 1234)),
        latitude: -33.8688197,
        longitude: 151.2092955,
        accuracy: 3.2,
        altitude: 58.4,
        altitudeAccuracy: 6,
        speed: 13.9,
        heading: 271.5,
      );

      await store.append(journey.id, precise);
      final stored = (await store.track(journey.id)).single.single;

      expect(stored, precise);
      expect(stored.time.isUtc, isTrue);
    });
  });

  group('pause, resume and end', () {
    test('each resume opens a new segment and fixes stay in theirs', () async {
      final journey = await store.startJourney(JourneyMode.expedition, at: t0);
      await store.append(journey.id, fixAt(1));
      await store.pause(journey.id, at: t0.add(const Duration(seconds: 2)));
      await store.resume(journey.id, at: t0.add(const Duration(seconds: 60)));
      await store.append(journey.id, fixAt(61));

      final segments = await store.segmentsOf(journey.id);
      expect(segments.map((s) => s.endReason), [SegmentEnd.paused, null]);
      expect(segments.last.startedAt, t0.add(const Duration(seconds: 60)));
      expect(await store.track(journey.id), [
        [fixAt(1)],
        [fixAt(61)],
      ]);
    });

    test('repeated transitions are no-ops', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);
      final later = t0.add(const Duration(minutes: 5));

      await store.pause(journey.id, at: t0);
      await store.pause(journey.id, at: later);
      await store.resume(journey.id, at: later);
      await store.resume(journey.id, at: later);
      await store.end(journey.id, at: later);
      await store.end(journey.id, at: later.add(const Duration(hours: 1)));

      final segments = await store.segmentsOf(journey.id);
      expect(segments, hasLength(2));
      expect(segments.first.endedAt, t0);
      expect(segments.last.endReason, SegmentEnd.ended);
      final ended = (await store.allJourneys()).single;
      expect(ended.status, JourneyStatus.ended);
      expect(ended.endedAt, later);
    });

    test('an ended journey cannot be resumed', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);
      await store.end(journey.id, at: t0);

      expect(() => store.resume(journey.id, at: t0), throwsStateError);
    });

    test(
      'ending while paused keeps the pause as the last segment end',
      () async {
        final journey = await store.startJourney(JourneyMode.road, at: t0);
        final paused = t0.add(const Duration(minutes: 1));
        await store.pause(journey.id, at: paused);

        await store.end(journey.id, at: t0.add(const Duration(minutes: 9)));

        final segment = (await store.segmentsOf(journey.id)).single;
        expect(segment.endedAt, paused);
        expect(segment.endReason, SegmentEnd.paused);
      },
    );
  });

  group('recoverInterrupted', () {
    test('closes the open segment at the last stored fix', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);
      await store.append(journey.id, fixAt(1));
      await store.append(journey.id, fixAt(7));

      final recovered = await store.recoverInterrupted();

      expect(recovered?.id, journey.id);
      expect(recovered?.status, JourneyStatus.paused);
      final segment = (await store.segmentsOf(journey.id)).single;
      expect(segment.endedAt, fixAt(7).time);
      expect(segment.endReason, SegmentEnd.interrupted);
    });

    test('ends a segment without fixes at its own start', () async {
      await store.startJourney(JourneyMode.road, at: t0);

      final recovered = await store.recoverInterrupted();

      final segment = (await store.segmentsOf(recovered!.id)).single;
      expect(segment.endedAt, t0);
      expect(segment.endReason, SegmentEnd.interrupted);
    });

    test('is idempotent and leaves paused or ended journeys alone', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);
      await store.pause(journey.id, at: t0);
      expect(await store.recoverInterrupted(), isNull);

      await store.resume(journey.id, at: t0.add(const Duration(seconds: 9)));
      expect(await store.recoverInterrupted(), isNotNull);
      expect(await store.recoverInterrupted(), isNull);

      final reasons = (await store.segmentsOf(
        journey.id,
      )).map((s) => s.endReason);
      expect(reasons, [SegmentEnd.paused, SegmentEnd.interrupted]);
    });

    test('a recovered journey resumes into a fresh segment', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);
      await store.append(journey.id, fixAt(1));
      await store.recoverInterrupted();

      await store.resume(journey.id, at: t0.add(const Duration(minutes: 3)));
      await store.append(journey.id, fixAt(181));

      expect(await store.track(journey.id), [
        [fixAt(1)],
        [fixAt(181)],
      ]);
    });
  });

  group('deleteJourney', () {
    test('removes the journey with its segments and fixes', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);
      await store.append(journey.id, fixAt(1));
      await store.end(journey.id, at: t0);

      await store.deleteJourney(journey.id);

      expect(await store.allJourneys(), isEmpty);
      expect(await store.select(store.segments).get(), isEmpty);
      expect(await store.select(store.trackPoints).get(), isEmpty);
    });

    test('refuses to delete an active journey', () async {
      final journey = await store.startJourney(JourneyMode.road, at: t0);

      expect(() => store.deleteJourney(journey.id), throwsStateError);
    });
  });

  test(
    'every fix reported as stored survives the process being killed',
    () async {
      final dir = await Directory.systemTemp.createTemp('tripping_kill_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/journeys.sqlite');

      final writer = await Process.start(_dartExecutable(), [
        'run',
        'test/support/record_until_killed.dart',
        file.path,
      ]);
      final stderrText = writer.stderr.transform(utf8.decoder).join();
      var reported = 0;
      final enough = Completer<void>();
      writer.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            reported = int.parse(line.split(' ').last);
            if (reported >= 200 && !enough.isCompleted) {
              writer.kill(ProcessSignal.sigkill);
              enough.complete();
            }
          });
      await enough.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () async =>
            fail('writer never got going: ${await stderrText}'),
      );
      expect(await writer.exitCode, isNot(0));

      final reopened = JourneyStore.file(file);
      addTearDown(reopened.close);
      final journey = await reopened.activeJourney();
      expect(journey?.status, JourneyStatus.recording);
      final stored = (await reopened.track(journey!.id)).single;
      expect(stored.length, greaterThanOrEqualTo(reported));

      await reopened.recoverInterrupted();
      final segment = (await reopened.segmentsOf(journey.id)).single;
      expect(segment.endReason, SegmentEnd.interrupted);
      expect(segment.endedAt, stored.last.time);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return 'dart';
  return '$flutterRoot/bin/cache/dart-sdk/bin/dart';
}
