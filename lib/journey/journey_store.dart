import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database, OpenMode, sqlite3;
import 'package:uuid/uuid.dart';

import 'journey.dart';
import 'simplify.dart';

part 'journey_store.g.dart';

/// Outcome of offering a fix to [JourneyStore.append].
enum AppendResult {
  /// Committed to disk.
  stored,

  /// A fix with the same time is already stored for this journey.
  duplicate,

  /// The journey has no open segment: it is paused, ended or unknown.
  notRecording,
}

/// Durable record of journeys, their segments and track points.
///
/// Durability contract:
/// - Every lifecycle transition is one transaction, so a crash leaves a
///   journey either before or after a transition, never in between.
/// - Once [append] completes, the fix survives the app process being killed.
///   With WAL and `synchronous = NORMAL`, only a whole-device power loss can
///   drop the most recent commits.
/// - After a process death the active journey still reads as recording;
///   [recoverInterrupted] turns that into an honest, closed segment.
@DriftDatabase(include: {'schema.drift'})
class JourneyStore extends _$JourneyStore {
  JourneyStore(super.executor) : _file = null;

  JourneyStore._file(super.executor, this._file);

  /// Opens the database in [file] on a background isolate, so disk I/O never
  /// blocks the UI isolate.
  factory JourneyStore.file(File file) => JourneyStore._file(
    NativeDatabase.createInBackground(file, setup: _configureConnection),
    file,
  );

  /// The database file, when there is one: long tracks are read from it on
  /// a separate isolate.
  final File? _file;

  static void _configureConnection(Database db) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
  }

  static const _uuid = Uuid();

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        for (final column in <GeneratedColumn>[
          journeys.summaryVersion,
          journeys.meters,
          journeys.movingMs,
          journeys.recordedMs,
          journeys.outline,
        ]) {
          await m.addColumn(journeys, column);
        }
      }
      if (from < 3) {
        await m.createTable(waypoints);
        await m.createIndex(waypointsByJourney);
      }
      if (from < 4) {
        await m.createTable(routes);
        await m.createTable(recentPlaces);
      }
      if (from < 5) await m.createTable(memberships);
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );

  /// The journey that is recording or paused, if any. There is at most one.
  Future<JourneyRow?> activeJourney() =>
      (select(journeys)..where(
            (j) => j.status.isInValues([
              JourneyStatus.recording,
              JourneyStatus.paused,
            ]),
          ))
          .getSingleOrNull();

  /// All journeys, newest first.
  Future<List<JourneyRow>> allJourneys() => (select(
    journeys,
  )..orderBy([(j) => OrderingTerm.desc(j.createdAt)])).get();

  /// Journeys that have ended, newest first.
  Future<List<JourneyRow>> endedJourneys() =>
      (select(journeys)
            ..where((j) => j.status.equalsValue(JourneyStatus.ended))
            ..orderBy([(j) => OrderingTerm.desc(j.createdAt)]))
          .get();

  /// Caches a summary derived from an ended journey's track. [version] says
  /// which rules derived it, so a newer app can derive it again.
  Future<void> saveSummary(
    int journeyId, {
    required int version,
    required double meters,
    required Duration movingTime,
    required Duration recordedTime,
    required String outline,
  }) => (update(journeys)..where((j) => j.id.equals(journeyId))).write(
    JourneysCompanion(
      summaryVersion: Value(version),
      meters: Value(meters),
      movingMs: Value(movingTime.inMilliseconds),
      recordedMs: Value(recordedTime.inMilliseconds),
      outline: Value(outline),
    ),
  );

  /// Creates a journey that is recording from [at], with its first segment
  /// open. Throws [StateError] if another journey is still active.
  Future<JourneyRow> startJourney(JourneyMode mode, {required DateTime at}) =>
      transaction(() async {
        final active = await activeJourney();
        if (active != null) {
          throw StateError('Journey ${active.uuid} is still active');
        }
        final journey = await into(journeys).insertReturning(
          JourneysCompanion.insert(
            uuid: _uuid.v7(),
            mode: mode,
            status: JourneyStatus.recording,
            createdAt: at,
          ),
        );
        await into(segments).insert(
          SegmentsCompanion.insert(
            journeyId: journey.id,
            seq: 0,
            startedAt: at,
          ),
        );
        return journey;
      });

  /// Stores [fix] in the journey's open segment.
  ///
  /// Accepts fixes in any time order; deciding which fixes are plausible is
  /// the caller's job. Re-delivering a fix is harmless.
  Future<AppendResult> append(int journeyId, Fix fix) async {
    final inserted = await customUpdate(
      'INSERT INTO track_points (journey_id, time, segment, latitude, '
      'longitude, accuracy, altitude, altitude_accuracy, speed, heading) '
      'SELECT journey_id, ?, seq, ?, ?, ?, ?, ?, ?, ? FROM segments '
      'WHERE journey_id = ? AND ended_at IS NULL '
      'ON CONFLICT DO NOTHING',
      variables: [
        Variable(const UtcMillis().toSql(fix.time)),
        Variable(fix.latitude),
        Variable(fix.longitude),
        Variable(fix.accuracy),
        Variable(fix.altitude),
        Variable(fix.altitudeAccuracy),
        Variable(fix.speed),
        Variable(fix.heading),
        Variable(journeyId),
      ],
      updates: {trackPoints},
      updateKind: UpdateKind.insert,
    );
    if (inserted == 1) return AppendResult.stored;
    return await _openSegment(journeyId) == null
        ? AppendResult.notRecording
        : AppendResult.duplicate;
  }

  /// Closes the open segment. A no-op unless the journey is recording.
  Future<void> pause(int journeyId, {required DateTime at}) =>
      transaction(() async {
        final journey = await _journey(journeyId);
        if (journey.status != JourneyStatus.recording) return;
        await _closeOpenSegment(journeyId, at, SegmentEnd.paused);
        await _setStatus(journeyId, JourneyStatus.paused);
      });

  /// Opens the next segment. A no-op if already recording; an ended journey
  /// cannot be resumed.
  Future<void> resume(int journeyId, {required DateTime at}) =>
      transaction(() async {
        final journey = await _journey(journeyId);
        switch (journey.status) {
          case JourneyStatus.recording:
            return;
          case JourneyStatus.ended:
            throw StateError('Journey ${journey.uuid} has ended');
          case JourneyStatus.paused:
            final count =
                await (selectOnly(segments)
                      ..addColumns([segments.seq.count()])
                      ..where(segments.journeyId.equals(journeyId)))
                    .map((row) => row.read(segments.seq.count())!)
                    .getSingle();
            await into(segments).insert(
              SegmentsCompanion.insert(
                journeyId: journeyId,
                seq: count,
                startedAt: at,
              ),
            );
            await _setStatus(journeyId, JourneyStatus.recording);
        }
      });

  /// Ends the journey. A no-op if it has already ended.
  Future<void> end(int journeyId, {required DateTime at}) =>
      transaction(() async {
        final journey = await _journey(journeyId);
        if (journey.status == JourneyStatus.ended) return;
        await _closeOpenSegment(journeyId, at, SegmentEnd.ended);
        await (update(journeys)..where((j) => j.id.equals(journeyId))).write(
          JourneysCompanion(
            status: const Value(JourneyStatus.ended),
            endedAt: Value(at),
          ),
        );
      });

  /// Closes the open segment of a journey whose recorder no longer exists,
  /// for example because the OS killed the process. The journey becomes
  /// paused, and its segment ends at the last stored fix: nothing is known
  /// about what happened after it.
  ///
  /// Call only when no recorder is running in this process. Returns the
  /// recovered journey, or null if there was nothing to recover.
  Future<JourneyRow?> recoverInterrupted() => transaction(() async {
    final active = await activeJourney();
    if (active == null || active.status != JourneyStatus.recording) {
      return null;
    }
    final open = await _openSegment(active.id);
    if (open != null) {
      final lastFix = trackPoints.time.max();
      final lastFixTime =
          await (selectOnly(trackPoints)
                ..addColumns([lastFix])
                ..where(
                  trackPoints.journeyId.equals(active.id) &
                      trackPoints.segment.equals(open.seq),
                ))
              .map((row) => row.read(lastFix))
              .getSingle();
      await (update(segments)..where(
            (s) => s.journeyId.equals(active.id) & s.seq.equals(open.seq),
          ))
          .write(
            SegmentsCompanion(
              endedAt: Value(
                lastFixTime == null
                    ? open.startedAt
                    : const UtcMillis().fromSql(lastFixTime),
              ),
              endReason: const Value(SegmentEnd.interrupted),
            ),
          );
    }
    await _setStatus(active.id, JourneyStatus.paused);
    return _journey(active.id);
  });

  /// The journey's segments in order.
  Future<List<SegmentRow>> segmentsOf(int journeyId) =>
      (select(segments)
            ..where((s) => s.journeyId.equals(journeyId))
            ..orderBy([(s) => OrderingTerm.asc(s.seq)]))
          .get();

  /// The recorded track, one time-ordered list of fixes per segment. The
  /// outer list is indexed by segment number; a segment without fixes yields
  /// an empty list.
  ///
  /// A file-backed store reads on a separate isolate over its own read-only
  /// connection (WAL lets it read beside the writer), and hands the result
  /// back without copying: a day of fixes never blocks the UI isolate.
  Future<List<List<Fix>>> track(int journeyId) => simplifiedTrack(journeyId);

  /// [track], with fixes that stray less than [tolerance] metres from the
  /// simplified line dropped on the reading isolate (see `simplify`). No
  /// tolerance keeps every fix.
  Future<List<List<Fix>>> simplifiedTrack(
    int journeyId, {
    double? tolerance,
  }) async {
    final file = _file;
    if (file != null) {
      final path = file.path;
      return Isolate.run(() => _readTrack(path, journeyId, tolerance));
    }
    final segmentCount = (await segmentsOf(journeyId)).length;
    final track = List.generate(segmentCount, (_) => <Fix>[]);
    final rows =
        await (select(trackPoints)
              ..where((p) => p.journeyId.equals(journeyId))
              ..orderBy([(p) => OrderingTerm.asc(p.time)]))
            .get();
    for (final row in rows) {
      track[row.segment].add(
        Fix(
          time: row.time,
          latitude: row.latitude,
          longitude: row.longitude,
          accuracy: row.accuracy,
          altitude: row.altitude,
          altitudeAccuracy: row.altitudeAccuracy,
          speed: row.speed,
          heading: row.heading,
        ),
      );
    }
    return _simplified(track, tolerance);
  }

  /// Saves a waypoint on [journeyId]. Once this completes it is on disk.
  Future<WaypointRow> addWaypoint(
    int journeyId, {
    required WaypointKind kind,
    required DateTime at,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    DateTime? fixTime,
    String? name,
    String? note,
  }) => into(waypoints).insertReturning(
    WaypointsCompanion.insert(
      journeyId: journeyId,
      kind: kind,
      createdAt: at,
      latitude: latitude,
      longitude: longitude,
      accuracy: Value(accuracy),
      altitude: Value(altitude),
      fixTime: Value(fixTime),
      name: Value(name),
      note: Value(note),
    ),
  );

  /// Names or notes a waypoint; blank text clears it. Where it is never
  /// changes.
  Future<void> describeWaypoint(int id, {String? name, String? note}) {
    String? text(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    return (update(waypoints)..where((w) => w.id.equals(id))).write(
      WaypointsCompanion(name: Value(text(name)), note: Value(text(note))),
    );
  }

  Future<void> deleteWaypoint(int id) =>
      (delete(waypoints)..where((w) => w.id.equals(id))).go();

  SimpleSelectStatement<Waypoints, WaypointRow> _waypointsOf(int journeyId) =>
      select(waypoints)
        ..where((w) => w.journeyId.equals(journeyId))
        ..orderBy([(w) => OrderingTerm.asc(w.createdAt)]);

  /// The journey's waypoints in the order they were made.
  Future<List<WaypointRow>> waypointsOf(int journeyId) =>
      _waypointsOf(journeyId).get();

  /// [waypointsOf], again whenever they change.
  Stream<List<WaypointRow>> watchWaypoints(int journeyId) =>
      _waypointsOf(journeyId).watch();

  /// Sets where [journeyId] is going; any route planned before is dropped,
  /// since it led somewhere else.
  Future<void> setDestination(
    int journeyId, {
    required String name,
    String? detail,
    required double latitude,
    required double longitude,
  }) => into(routes).insertOnConflictUpdate(
    RoutesCompanion.insert(
      journeyId: Value(journeyId),
      destination: name,
      destinationDetail: Value(detail),
      latitude: latitude,
      longitude: longitude,
      // Said outright: on conflict, columns left out would keep the old
      // route, a way to somewhere else.
      kind: const Value(null),
      provider: const Value(null),
      computedAt: const Value(null),
      meters: const Value(null),
      seconds: const Value(null),
      geometry: const Value(null),
    ),
  );

  /// Keeps the way planned to the journey's destination.
  Future<void> saveRoute(
    int journeyId, {
    required RouteKind kind,
    required String provider,
    required DateTime computedAt,
    required double meters,
    double? seconds,
    required String geometry,
  }) => (update(routes)..where((r) => r.journeyId.equals(journeyId))).write(
    RoutesCompanion(
      kind: Value(kind),
      provider: Value(provider),
      computedAt: Value(computedAt),
      meters: Value(meters),
      seconds: Value(seconds),
      geometry: Value(geometry),
    ),
  );

  Future<void> clearDestination(int journeyId) =>
      (delete(routes)..where((r) => r.journeyId.equals(journeyId))).go();

  /// Puts [journeyId] in a group. A journey is in at most one group:
  /// joining another is refused rather than silently replacing it.
  Future<void> saveMembership(
    int journeyId, {
    required String groupId,
    required String secret,
    required GroupRole role,
    String? hostName,
    required DateTime at,
  }) => transaction(() async {
    if (await membershipOf(journeyId) != null) {
      throw StateError('Journey $journeyId is already in a group');
    }
    await into(memberships).insert(
      MembershipsCompanion.insert(
        journeyId: Value(journeyId),
        groupId: groupId,
        secret: secret,
        role: role,
        hostName: Value(hostName),
        joinedAt: at,
      ),
    );
  });

  Future<MembershipRow?> membershipOf(int journeyId) =>
      _membershipOf(journeyId).getSingleOrNull();

  Stream<MembershipRow?> watchMembership(int journeyId) =>
      _membershipOf(journeyId).watchSingleOrNull();

  SimpleSelectStatement<Memberships, MembershipRow> _membershipOf(
    int journeyId,
  ) => select(memberships)..where((m) => m.journeyId.equals(journeyId));

  SimpleSelectStatement<Routes, RouteRow> _routeOf(int journeyId) =>
      select(routes)..where((r) => r.journeyId.equals(journeyId));

  Future<RouteRow?> routeOf(int journeyId) =>
      _routeOf(journeyId).getSingleOrNull();

  Stream<RouteRow?> watchRoute(int journeyId) =>
      _routeOf(journeyId).watchSingleOrNull();

  /// Remembers a place chosen as a destination, keeping the [keep] most
  /// recent; choosing one again moves it to the top.
  Future<void> rememberPlace({
    required String name,
    String? detail,
    required double latitude,
    required double longitude,
    required DateTime at,
    int keep = 20,
  }) => transaction(() async {
    await (delete(recentPlaces)..where(
          (p) =>
              p.name.equals(name) &
              p.latitude.equals(latitude) &
              p.longitude.equals(longitude),
        ))
        .go();
    await into(recentPlaces).insert(
      RecentPlacesCompanion.insert(
        name: name,
        detail: Value(detail),
        latitude: latitude,
        longitude: longitude,
        usedAt: at,
      ),
    );
    final stale =
        await (select(recentPlaces)
              ..orderBy([(p) => OrderingTerm.desc(p.usedAt)])
              ..limit(1000, offset: keep))
            .get();
    for (final place in stale) {
      await (delete(recentPlaces)..where((p) => p.id.equals(place.id))).go();
    }
  });

  /// The places chosen as destinations most recently, newest first.
  Future<List<RecentPlaceRow>> latestPlaces({int limit = 8}) =>
      (select(recentPlaces)
            ..orderBy([(p) => OrderingTerm.desc(p.usedAt)])
            ..limit(limit))
          .get();

  /// Deletes an inactive journey with all of its segments and fixes.
  Future<void> deleteJourney(int journeyId) => transaction(() async {
    final journey = await _journey(journeyId);
    if (journey.status != JourneyStatus.ended) {
      throw StateError('End journey ${journey.uuid} before deleting it');
    }
    await (delete(journeys)..where((j) => j.id.equals(journeyId))).go();
  });

  Future<JourneyRow> _journey(int journeyId) async {
    final journey = await (select(
      journeys,
    )..where((j) => j.id.equals(journeyId))).getSingleOrNull();
    if (journey == null) throw StateError('No journey with id $journeyId');
    return journey;
  }

  Future<SegmentRow?> _openSegment(int journeyId) =>
      (select(segments)
            ..where((s) => s.journeyId.equals(journeyId) & s.endedAt.isNull()))
          .getSingleOrNull();

  Future<void> _closeOpenSegment(int journeyId, DateTime at, SegmentEnd why) =>
      (update(segments)
            ..where((s) => s.journeyId.equals(journeyId) & s.endedAt.isNull()))
          .write(SegmentsCompanion(endedAt: Value(at), endReason: Value(why)));

  Future<void> _setStatus(int journeyId, JourneyStatus status) =>
      (update(journeys)..where((j) => j.id.equals(journeyId))).write(
        JourneysCompanion(status: Value(status)),
      );
}

List<List<Fix>> _simplified(List<List<Fix>> track, double? tolerance) =>
    tolerance == null
    ? track
    : [for (final segment in track) simplify(segment, tolerance)];

/// Reads a journey's track straight from the database file. Runs on its own
/// isolate; the columns match the `track_points` table.
List<List<Fix>> _readTrack(String path, int journeyId, double? tolerance) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final segmentCount =
        db
                .select('SELECT COUNT(*) FROM segments WHERE journey_id = ?', [
                  journeyId,
                ])
                .single
                .columnAt(0)
            as int;
    final track = List.generate(segmentCount, (_) => <Fix>[]);
    final statement = db.prepare(
      'SELECT segment, time, latitude, longitude, accuracy, altitude, '
      'altitude_accuracy, speed, heading FROM track_points '
      'WHERE journey_id = ? ORDER BY time',
    );
    try {
      final rows = statement.selectCursor([journeyId]);
      while (rows.moveNext()) {
        final row = rows.current;
        track[row.columnAt(0) as int].add(
          Fix(
            time: DateTime.fromMillisecondsSinceEpoch(
              row.columnAt(1) as int,
              isUtc: true,
            ),
            latitude: row.columnAt(2) as double,
            longitude: row.columnAt(3) as double,
            accuracy: (row.columnAt(4) as num?)?.toDouble(),
            altitude: (row.columnAt(5) as num?)?.toDouble(),
            altitudeAccuracy: (row.columnAt(6) as num?)?.toDouble(),
            speed: (row.columnAt(7) as num?)?.toDouble(),
            heading: (row.columnAt(8) as num?)?.toDouble(),
          ),
        );
      }
    } finally {
      statement.close();
    }
    return _simplified(track, tolerance);
  } finally {
    db.close();
  }
}
