import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/recording/recorder.dart';

import '../support/fakes.dart';

void main() {
  for (final days in [2, 3, 5]) {
    test(
      'SIGKILL then $days simulated days preserves paused identity, fixes and segment',
      () async {
        final dir = await Directory.systemTemp.createTemp('tripping_paused_');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/journeys.sqlite');
        final flutter = Platform.environment['FLUTTER_ROOT'];
        final dart = flutter == null
            ? 'dart'
            : '$flutter/bin/cache/dart-sdk/bin/dart';
        final child = await Process.start(dart, [
          'run',
          'test/support/pause_until_killed.dart',
          file.path,
        ]);
        addTearDown(() {
          child.kill(ProcessSignal.sigkill);
        });
        final error = child.stderr.transform(utf8.decoder).join();
        final ready = child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.contains('PAUSED_READY '))
            .map(
              (line) => line.substring(
                line.indexOf('PAUSED_READY ') + 'PAUSED_READY '.length,
              ),
            )
            .first;
        final fields = (await ready.timeout(
          const Duration(seconds: 30),
          onTimeout: () async {
            child.kill(ProcessSignal.sigkill);
            throw StateError('Synthetic writer failed: ${await error}');
          },
        )).split(' ');
        child.kill(ProcessSignal.sigkill);
        expect(await child.exitCode, isNot(0));
        final store = JourneyStore.file(file);
        addTearDown(store.close);
        final location = FakeLocation();
        final now = DateTime.utc(2026, 10, 29).add(Duration(days: days));
        final recorder = await Recorder.open(store, location, clock: () => now);
        addTearDown(recorder.close);
        final paused = recorder.state as Paused;
        expect(paused.journey.uuid, fields[1]);
        expect(location.requests, 0);
        expect(location.listening, isFalse);
        expect((await store.track(paused.journey.id)).single, hasLength(3));
        expect(
          (await store.segmentsOf(paused.journey.id)).single.endReason,
          SegmentEnd.paused,
        );
        await recorder.resume();
        expect((recorder.state as Recording).journey.uuid, fields[1]);
        final parts = await store.segmentsOf(paused.journey.id);
        expect(parts, hasLength(2));
        expect(parts.last.startedAt, now);
      },
    );
  }
}
