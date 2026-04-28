// Replays journeys pulled from a phone through the app's real recording code
// and prints aggregates and relative metres. It never prints coordinates:
// the input is the owner's location history (see AI_CONTEXT/CURRENT_STATE.md
// for how to pull it, and delete the copy afterwards).
//
//   dart run tool/field_report.dart <dir with journeys.sqlite + raw_fixes.jsonl> <ids, e.g. 5,6,7> [policy override JSON]
//
// Override keys: maxAccuracy, gateFactor, minGate, maxSpeed, minMovingSpeed,
// driftSpeed, confidentSpeed, movingGateFactor, relocateAfter.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tripping/journey/geo.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/recording/track_policy.dart';
import 'package:tripping/recording/track_stats.dart';

String q(Iterable<double> values) {
  final s = values.toList()..sort();
  if (s.isEmpty) return '-';
  String at(double p) => s[((s.length - 1) * p).round()].toStringAsFixed(2);
  return 'min ${at(0)} p50 ${at(.5)} p90 ${at(.9)} max ${at(1)}';
}

TrackPolicy policyFor(JourneyMode mode, Map<String, dynamic> o) {
  final b = TrackPolicy.of(mode);
  double d(String k, double v) => (o[k] as num?)?.toDouble() ?? v;
  return TrackPolicy(
    maxAccuracy: d('maxAccuracy', b.maxAccuracy),
    gateFactor: d('gateFactor', b.gateFactor),
    minGate: d('minGate', b.minGate),
    maxSpeed: d('maxSpeed', b.maxSpeed),
    minMovingSpeed: d('minMovingSpeed', b.minMovingSpeed),
    driftSpeed: d('driftSpeed', b.driftSpeed),
    confidentSpeed: d('confidentSpeed', b.confidentSpeed),
    movingGateFactor: d('movingGateFactor', b.movingGateFactor),
    relocateAfter: (o['relocateAfter'] as num?)?.toInt() ?? b.relocateAfter,
  );
}

Future<void> main(List<String> args) async {
  final dir = args[0];
  final ids = args[1].split(',').map(int.parse);
  final override = args.length > 2
      ? jsonDecode(args[2]) as Map<String, dynamic>
      : <String, dynamic>{};
  final store = JourneyStore.file(File('$dir/journeys.sqlite'));
  final rawLines = File('$dir/raw_fixes.jsonl')
      .readAsLinesSync()
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
  for (final id in ids) {
    final journey = (await store.allJourneys()).firstWhere((j) => j.id == id);
    final policy = policyFor(journey.mode, override);
    final track = await store.track(id);
    final fixes = [for (final s in track) ...s];
    final stats = TrackStats.replay(policy, track);
    var doppler = 0.0, naive = 0.0, far = 0.0;
    for (var i = 1; i < fixes.length; i++) {
      final dt =
          fixes[i].time.difference(fixes[i - 1].time).inMilliseconds / 1000;
      doppler += ((fixes[i].speed ?? 0) + (fixes[i - 1].speed ?? 0)) / 2 * dt;
      naive += fixes[i - 1].metersTo(fixes[i]);
      far = max(far, fixes.first.metersTo(fixes[i]));
    }
    var smooth = 0.0;
    (double, double) avg(int i) {
      var la = 0.0, lo = 0.0;
      for (var k = -2; k <= 2; k++) {
        la += fixes[i + k].latitude;
        lo += fixes[i + k].longitude;
      }
      return (la / 5, lo / 5);
    }

    for (var i = 3; i < fixes.length - 2; i++) {
      final a = avg(i - 1), b = avg(i);
      smooth += metersBetween(a.$1, a.$2, b.$1, b.$2);
    }
    final raw = [
      for (final m in rawLines)
        if (m['event'] == 'fix' &&
            !DateTime.parse(
              m['arrived'] as String,
            ).isBefore(journey.createdAt) &&
            !DateTime.parse(
              m['arrived'] as String,
            ).isAfter(journey.endedAt!.add(const Duration(seconds: 2))))
          m,
    ];
    final gaps = [
      for (var i = 1; i < raw.length; i++)
        DateTime.parse(raw[i]['arrived'] as String)
                .difference(DateTime.parse(raw[i - 1]['arrived'] as String))
                .inMilliseconds /
            1000,
    ];
    final speeds = [
      for (final f in fixes)
        if (f.speed != null) f.speed!,
    ];
    stdout.writeln(
      'J$id ${journey.mode.name} segments ${track.length} ${journey.endedAt!.difference(journey.createdAt).inSeconds}s '
      'stored ${fixes.length}/${raw.length} delivered | APP ${stats.meters.toStringAsFixed(1)} m moving ${stats.movingTime.inSeconds}s | '
      'speed*time ${doppler.toStringAsFixed(1)} m | smoothed5 ${smooth.toStringAsFixed(1)} m | naive ${naive.toStringAsFixed(1)} m | '
      'start-end ${fixes.first.metersTo(fixes.last).toStringAsFixed(1)} m | farthest ${far.toStringAsFixed(1)} m',
    );
    stdout.writeln(
      'J$id   gap s: ${q(gaps)} | acc m: ${q([for (final f in fixes)
        if (f.accuracy != null) f.accuracy!])} | '
      'speed m/s (${speeds.length}/${fixes.length}): ${q(speeds)} | speed<0.8: ${speeds.where((s) => s < .8).length}',
    );
  }
  await store.close();
}
