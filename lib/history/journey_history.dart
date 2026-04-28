import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../journey/simplify.dart';
import 'gpx.dart' as gpx;
import '../recording/track_policy.dart';
import '../recording/track_stats.dart';

/// Raise when the distance rules or the outline change: summaries stored by
/// older rules are then derived again from their tracks.
const summaryVersion = 1;

/// Most points kept in a journey's outline, across all its segments.
const _outlinePoints = 120;

/// A point of a journey's outline.
typedef OutlinePoint = ({double latitude, double longitude});

/// An ended journey with the numbers and shape the history shows.
class PastJourney {
  const PastJourney({
    required this.journey,
    required this.meters,
    required this.movingTime,
    required this.recordedTime,
    required this.outline,
  });

  final JourneyRow journey;
  final double meters;
  final Duration movingTime;

  /// Time spent recording, leaving out pauses and interruptions.
  final Duration recordedTime;

  /// Per segment, a few points for a thumbnail. Segments stay separate:
  /// nothing is known about the way between them.
  final List<List<OutlinePoint>> outline;
}

/// Past journeys, read from the store. Summaries are a cache of what the
/// track says, so the track stays the only truth.
class JourneyHistory {
  JourneyHistory(this._store);

  final JourneyStore _store;

  /// Ended journeys, newest first. A summary that is missing or was derived
  /// by older rules is derived now and saved.
  Future<List<PastJourney>> load() async => [
    for (final row in await _store.endedJourneys()) await _summaryOf(row),
  ];

  /// The journey's track for drawing, one list per segment, with fixes that
  /// add nothing visible at [tolerance] metres dropped. Simplified off the
  /// UI isolate, so long journeys open without stutter.
  Future<List<List<Fix>>> trackOf(int journeyId, {double tolerance = 1}) async {
    final track = await _store.track(journeyId);
    return Isolate.run(
      () => [for (final segment in track) simplify(segment, tolerance)],
    );
  }

  Future<void> delete(int journeyId) => _store.deleteJourney(journeyId);

  /// The journey as GPX with every recorded fix, not the simplified drawing.
  Future<String> gpxOf(PastJourney past, {required String name}) async =>
      gpx.gpxOf(
        name: name,
        mode: past.journey.mode,
        startedAt: past.journey.createdAt,
        track: await _store.track(past.journey.id),
      );

  Future<PastJourney> _summaryOf(JourneyRow row) async {
    if (row.summaryVersion == summaryVersion) {
      return PastJourney(
        journey: row,
        meters: row.meters ?? 0,
        movingTime: Duration(milliseconds: row.movingMs ?? 0),
        recordedTime: Duration(milliseconds: row.recordedMs ?? 0),
        outline: decodeOutline(row.outline ?? '[]'),
      );
    }
    final track = await _store.track(row.id);
    final segments = await _store.segmentsOf(row.id);
    final stats = TrackStats.replay(TrackPolicy.of(row.mode), track);
    var recorded = Duration.zero;
    for (final segment in segments) {
      final end = segment.endedAt ?? row.endedAt ?? segment.startedAt;
      if (end.isAfter(segment.startedAt)) {
        recorded += end.difference(segment.startedAt);
      }
    }
    final outline = outlineOf(track);
    await _store.saveSummary(
      row.id,
      version: summaryVersion,
      meters: stats.meters,
      movingTime: stats.movingTime,
      recordedTime: recorded,
      outline: encodeOutline(outline),
    );
    return PastJourney(
      journey: row,
      meters: stats.meters,
      movingTime: stats.movingTime,
      recordedTime: recorded,
      outline: outline,
    );
  }
}

/// A thumbnail's worth of [track]: at most [_outlinePoints] points, with
/// detail dropped evenly relative to the journey's size.
List<List<OutlinePoint>> outlineOf(List<List<Fix>> track) {
  final fixes = [for (final segment in track) ...segment];
  if (fixes.isEmpty) return const [];
  var south = fixes.first.latitude, north = south;
  var west = fixes.first.longitude, east = west;
  for (final fix in fixes) {
    south = min(south, fix.latitude);
    north = max(north, fix.latitude);
    west = min(west, fix.longitude);
    east = max(east, fix.longitude);
  }
  const metersPerDegree = 111195.0;
  final extent = max(
    (north - south) * metersPerDegree,
    (east - west) * metersPerDegree * cos((south + north) / 2 * pi / 180),
  );
  var tolerance = max(1.0, extent / 200);
  while (true) {
    final simple = [
      for (final segment in track)
        if (segment.isNotEmpty) simplify(segment, tolerance),
    ];
    final points = simple.fold(0, (sum, segment) => sum + segment.length);
    if (points <= _outlinePoints || tolerance > extent) {
      return [
        for (final segment in simple)
          [
            for (final fix in segment)
              (latitude: fix.latitude, longitude: fix.longitude),
          ],
      ];
    }
    tolerance *= 2;
  }
}

/// Outline as JSON: per segment, `[longitude, latitude]` pairs to about a
/// metre.
String encodeOutline(List<List<OutlinePoint>> outline) => jsonEncode([
  for (final segment in outline)
    [
      for (final point in segment)
        [_round(point.longitude), _round(point.latitude)],
    ],
]);

List<List<OutlinePoint>> decodeOutline(String json) => [
  for (final segment in jsonDecode(json) as List<Object?>)
    [
      for (final pair in (segment! as List<Object?>).cast<List<Object?>>())
        (
          latitude: (pair[1]! as num).toDouble(),
          longitude: (pair[0]! as num).toDouble(),
        ),
    ],
];

double _round(double degrees) => (degrees * 1e5).roundToDouble() / 1e5;
