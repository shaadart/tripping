// Records fixes into the journey database at args[0] as fast as it can,
// printing "stored <n>" after each commit, until something kills it.
// Driven by journey_store_test.dart to prove fixes survive SIGKILL.
import 'dart:io';

import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

Future<void> main(List<String> args) async {
  final store = JourneyStore.file(File(args.single));
  final start = DateTime.utc(2026, 10, 27, 6, 30);
  final journey = await store.startJourney(JourneyMode.expedition, at: start);
  for (var n = 1; ; n++) {
    final fix = Fix(
      time: start.add(Duration(milliseconds: 250 * n)),
      latitude: 32.2432 + n * 1e-5,
      longitude: 77.1892,
      accuracy: 5,
    );
    if (await store.append(journey.id, fix) != AppendResult.stored) {
      throw StateError('fix $n was not stored');
    }
    stdout.writeln('stored $n');
  }
}
