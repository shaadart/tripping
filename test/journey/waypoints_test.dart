import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

final t0 = DateTime.utc(2026, 10, 28, 6);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late JourneyStore store;

  setUp(() => store = JourneyStore(NativeDatabase.memory()));
  tearDown(() => store.close());

  Future<WaypointRow> mark(int journeyId, int second, {String? name}) =>
      store.addWaypoint(
        journeyId,
        kind: WaypointKind.marked,
        at: t0.add(Duration(seconds: second)),
        latitude: 32.24,
        longitude: 77.19,
        accuracy: 6,
        altitude: 2050,
        fixTime: t0.add(Duration(seconds: second - 1)),
        name: name,
      );

  test(
    'a marked waypoint keeps its fix: accuracy, altitude and GPS time',
    () async {
      final journey = await store.startJourney(JourneyMode.expedition, at: t0);
      final waypoint = await mark(journey.id, 10);

      final stored = (await store.waypointsOf(journey.id)).single;
      expect(stored, waypoint);
      expect(stored.kind, WaypointKind.marked);
      expect(stored.accuracy, 6);
      expect(stored.altitude, 2050);
      expect(stored.fixTime, t0.add(const Duration(seconds: 9)));
      expect(stored.name, isNull);
    },
  );

  test('waypoints come in the order they were made, per journey', () async {
    final a = await store.startJourney(JourneyMode.expedition, at: t0);
    await mark(a.id, 30, name: 'second');
    await mark(a.id, 10, name: 'first');
    await store.end(a.id, at: t0.add(const Duration(minutes: 1)));
    final b = await store.startJourney(JourneyMode.road, at: t0);
    await mark(b.id, 5, name: 'other journey');

    expect((await store.waypointsOf(a.id)).map((w) => w.name), [
      'first',
      'second',
    ]);
  });

  test('naming trims, and blank text clears', () async {
    final journey = await store.startJourney(JourneyMode.expedition, at: t0);
    final waypoint = await mark(journey.id, 1);

    await store.describeWaypoint(waypoint.id, name: '  Spring ', note: 'cold');
    var stored = (await store.waypointsOf(journey.id)).single;
    expect((stored.name, stored.note), ('Spring', 'cold'));

    await store.describeWaypoint(waypoint.id, name: ' ', note: null);
    stored = (await store.waypointsOf(journey.id)).single;
    expect((stored.name, stored.note), (null, null));
    expect(stored.latitude, 32.24);
  });

  test('deleting a waypoint, or its journey, removes it', () async {
    final journey = await store.startJourney(JourneyMode.expedition, at: t0);
    final kept = await mark(journey.id, 1);
    final gone = await mark(journey.id, 2);
    await store.deleteWaypoint(gone.id);
    expect(await store.waypointsOf(journey.id), [kept]);

    await store.end(journey.id, at: t0.add(const Duration(minutes: 1)));
    await store.deleteJourney(journey.id);
    expect(await store.waypointsOf(journey.id), isEmpty);
  });

  test('watching sees every change', () async {
    final journey = await store.startJourney(JourneyMode.expedition, at: t0);
    final seen = <int>[];
    final watching = store
        .watchWaypoints(journey.id)
        .listen((list) => seen.add(list.length));
    await pumpEventQueue();
    final waypoint = await mark(journey.id, 1);
    await pumpEventQueue();
    await store.deleteWaypoint(waypoint.id);
    await pumpEventQueue();
    await watching.cancel();
    expect(seen, [0, 1, 0]);
  });

  test('a waypoint is on disk as soon as it is saved', () async {
    final dir = Directory.systemTemp.createTempSync('tripping_waypoints');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/journeys.sqlite');
    final onDisk = JourneyStore.file(file);
    addTearDown(onDisk.close);
    final journey = await onDisk.startJourney(JourneyMode.expedition, at: t0);
    await onDisk.addWaypoint(
      journey.id,
      kind: WaypointKind.planned,
      at: t0,
      latitude: 32.3,
      longitude: 77.2,
    );

    // Another connection, as after a process death, sees it at once.
    final reader = sqlite3.open(file.path, mode: OpenMode.readOnly);
    addTearDown(reader.close);
    expect(
      reader.select('SELECT kind FROM waypoints').single['kind'],
      'planned',
    );
  });
}
