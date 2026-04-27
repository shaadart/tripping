// Runs the journey store on a real device: proves SQLite loads there, that
// commits survive closing and reopening the file, and measures append latency.
//
//   flutter test integration_test -d <device-id>
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

const fixCount = 3000;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('fixes commit, survive reopening, and append latency is logged', () async {
    final dir = await Directory.systemTemp.createTemp('journeys_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/journeys.sqlite');
    final start = DateTime.utc(2026, 10, 27, 6, 30);

    final store = JourneyStore.file(file);
    final journey = await store.startJourney(JourneyMode.road, at: start);
    final micros = <int>[];
    final clock = Stopwatch();
    for (var n = 1; n <= fixCount; n++) {
      final fix = Fix(
        time: start.add(Duration(seconds: n)),
        latitude: 32.2432 + n * 1e-5,
        longitude: 77.1892,
        accuracy: 4,
        altitude: 2050,
        altitudeAccuracy: 3,
        speed: 13.9,
        heading: 270,
      );
      clock
        ..reset()
        ..start();
      final result = await store.append(journey.id, fix);
      micros.add(clock.elapsedMicroseconds);
      expect(result, AppendResult.stored);
    }
    await store.close();

    final reopened = JourneyStore.file(file);
    addTearDown(reopened.close);
    final track = await reopened.track(journey.id);
    expect(track.single, hasLength(fixCount));
    expect((await reopened.activeJourney())?.id, journey.id);

    micros.sort();
    int at(double q) => micros[((micros.length - 1) * q).round()];
    final bytes = file.lengthSync() + _sizeOf('${file.path}-wal');
    final mode = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug';
    debugPrint(
      'DEVICE_STORE fixes=$fixCount '
      'append_us p50=${at(.5)} p95=${at(.95)} p99=${at(.99)} max=${micros.last} '
      'bytes_per_fix=${(bytes / fixCount).toStringAsFixed(1)} mode=$mode',
    );
  });
}

int _sizeOf(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : 0;
}
