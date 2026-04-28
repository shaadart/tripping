import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

final t0 = DateTime.utc(2026, 10, 27, 6, 30);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late JourneyStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tripping_track');
    store = JourneyStore.file(File('${dir.path}/journeys.sqlite'));
  });
  tearDown(() async {
    await store.close();
    dir.deleteSync(recursive: true);
  });

  test('a file-backed track reads back every field, in its segments', () async {
    final full = Fix(
      time: t0.add(const Duration(seconds: 1)),
      latitude: 32.2432101,
      longitude: 77.1892202,
      accuracy: 4.5,
      altitude: 2050.25,
      altitudeAccuracy: 3,
      speed: 1.25,
      heading: 359.5,
    );
    final bare = Fix(
      time: t0.add(const Duration(seconds: 2)),
      latitude: -33.5,
      longitude: -70.25,
    );
    final later = Fix(
      time: t0.add(const Duration(minutes: 5)),
      latitude: 32.25,
      longitude: 77.19,
      accuracy: 8,
    );
    final journey = await store.startJourney(JourneyMode.road, at: t0);
    await store.append(journey.id, full);
    await store.append(journey.id, bare);
    await store.pause(journey.id, at: t0.add(const Duration(minutes: 1)));
    await store.resume(journey.id, at: t0.add(const Duration(minutes: 2)));
    await store.pause(journey.id, at: t0.add(const Duration(minutes: 3)));
    await store.resume(journey.id, at: t0.add(const Duration(minutes: 4)));
    await store.append(journey.id, later);

    expect(await store.track(journey.id), [
      [full, bare],
      <Fix>[],
      [later],
    ]);
  });

  test('a file-backed track is simplified where it is read', () async {
    final journey = await store.startJourney(JourneyMode.road, at: t0);
    for (var s = 0; s < 100; s++) {
      await store.append(
        journey.id,
        Fix(
          time: t0.add(Duration(seconds: s)),
          latitude: 32 + s * 1e-5,
          longitude: 77,
        ),
      );
    }
    final simple = await store.simplifiedTrack(journey.id, tolerance: 1);
    expect(simple.single, hasLength(2));
    expect((await store.track(journey.id)).single, hasLength(100));
  });
}
