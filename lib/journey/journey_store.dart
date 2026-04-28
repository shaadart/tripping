import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:uuid/uuid.dart';

import 'journey.dart';

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
  JourneyStore(super.executor);

  /// Opens the database in [file] on a background isolate, so disk I/O never
  /// blocks the UI isolate.
  factory JourneyStore.file(File file) => JourneyStore(
    NativeDatabase.createInBackground(file, setup: _configureConnection),
  );

  static void _configureConnection(Database db) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
  }

  static const _uuid = Uuid();

  @override
  int get schemaVersion => 2;

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
  Future<List<List<Fix>>> track(int journeyId) async {
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
    return track;
  }

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
