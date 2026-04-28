import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

/// Schema v1 as shipped in `941d992`, frozen. Never edit: it stands for
/// databases already on phones.
const _schemaV1 = [
  '''CREATE TABLE journeys (
    id INTEGER NOT NULL PRIMARY KEY,
    uuid TEXT NOT NULL UNIQUE,
    mode TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    ended_at INTEGER)''',
  '''CREATE UNIQUE INDEX IF NOT EXISTS one_active_journey
    ON journeys (status IN ('recording', 'paused'))
    WHERE status IN ('recording', 'paused')''',
  '''CREATE TABLE segments (
    journey_id INTEGER NOT NULL REFERENCES journeys (id) ON DELETE CASCADE,
    seq INTEGER NOT NULL,
    started_at INTEGER NOT NULL,
    ended_at INTEGER,
    end_reason TEXT,
    PRIMARY KEY (journey_id, seq))''',
  '''CREATE TABLE track_points (
    journey_id INTEGER NOT NULL REFERENCES journeys (id) ON DELETE CASCADE,
    time INTEGER NOT NULL,
    segment INTEGER NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    accuracy REAL,
    altitude REAL,
    altitude_accuracy REAL,
    speed REAL,
    heading REAL,
    PRIMARY KEY (journey_id, time)) WITHOUT ROWID''',
];

final _t0 = DateTime.utc(2026, 10, 27, 6, 30).millisecondsSinceEpoch;

List<String> columnsOf(Database db, String table) => [
  for (final row in db.select('PRAGMA table_info($table)'))
    '${row['name']} ${row['type']} ${row['notnull']} ${row['pk']}',
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('tripping_migration'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'a v1 database upgrades to v2 with every journey and fix intact',
    () async {
      final file = File('${dir.path}/journeys.sqlite');
      final v1 = sqlite3.open(file.path);
      for (final statement in _schemaV1) {
        v1.execute(statement);
      }
      v1
        ..execute('PRAGMA user_version = 1')
        ..execute(
          "INSERT INTO journeys VALUES (1, 'u-1', 'expedition', 'ended', ?, ?)",
          [_t0, _t0 + 60000],
        )
        ..execute(
          "INSERT INTO journeys VALUES (2, 'u-2', 'road', 'recording', ?, NULL)",
          [_t0 + 120000],
        )
        ..execute("INSERT INTO segments VALUES (1, 0, ?, ?, 'ended')", [
          _t0,
          _t0 + 60000,
        ])
        ..execute('INSERT INTO segments VALUES (2, 0, ?, NULL, NULL)', [
          _t0 + 120000,
        ]);
      for (var second = 0; second < 60; second++) {
        v1.execute(
          'INSERT INTO track_points (journey_id, time, segment, latitude, '
          'longitude, accuracy) VALUES (1, ?, 0, ?, 77.19, 4)',
          [_t0 + second * 1000, 32.24 + second * 1e-5],
        );
      }
      v1.close();

      final store = JourneyStore.file(file);
      final ended = await store.endedJourneys();
      expect(ended.single.uuid, 'u-1');
      expect(ended.single.summaryVersion, isNull);
      expect(ended.single.meters, isNull);
      expect((await store.track(1)).single, hasLength(60));
      expect((await store.activeJourney())?.uuid, 'u-2');

      await store.saveSummary(
        1,
        version: 1,
        meters: 66.7,
        movingTime: const Duration(seconds: 50),
        recordedTime: const Duration(minutes: 1),
        outline: '[]',
      );
      final summarised = (await store.endedJourneys()).single;
      expect(summarised.meters, 66.7);
      expect(summarised.movingMs, 50000);
      expect(summarised.recordedMs, 60000);
      await store.close();

      // The upgraded table is exactly what a fresh install creates.
      final fresh = JourneyStore.file(File('${dir.path}/fresh.sqlite'));
      await fresh.activeJourney();
      await fresh.close();
      final upgraded = sqlite3.open(file.path);
      final created = sqlite3.open('${dir.path}/fresh.sqlite');
      expect(upgraded.select('PRAGMA user_version').single.values.single, 2);
      for (final table in ['journeys', 'segments', 'track_points']) {
        expect(columnsOf(upgraded, table), columnsOf(created, table));
      }
      upgraded.close();
      created.close();
    },
  );

  test('a fresh database starts at v2', () async {
    final store = JourneyStore(NativeDatabase.memory());
    final journey = await store.startJourney(
      JourneyMode.expedition,
      at: DateTime.utc(2026),
    );
    expect(journey.summaryVersion, isNull);
    expect(store.schemaVersion, 2);
    await store.close();
  });
}
