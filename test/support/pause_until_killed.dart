// Synthetic writer for paused-process-death recovery; no platform/network.
import 'dart:async';
import 'dart:io';

import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/recording/location_source.dart';
import 'package:tripping/recording/recorder.dart';

class Location implements LocationSource {
  final fixes = StreamController<Fix>(sync: true);
  @override
  Future<LocationAccess> requestAccess() async => LocationAccess.granted;
  @override
  Stream<Fix> watch(JourneyMode mode) => fixes.stream;
  @override
  Future<Fix?> lastKnown() async => null;
  @override
  Future<void> openSettingsFor(LocationAccess problem) async {}
}

Future<void> main(List<String> args) async {
  final store = JourneyStore.file(File(args.single));
  var now = DateTime.utc(2026, 10, 29);
  final location = Location();
  stderr.writeln('PROBE opening');
  final recorder = await Recorder.open(store, location, clock: () => now);
  stderr.writeln('PROBE starting');
  await recorder.start(JourneyMode.expedition);
  final id = (recorder.state as Recording).journey.id;
  for (var n = 0; n < 3; n++) {
    now = now.add(const Duration(seconds: 2));
    location.fixes.add(
      Fix(
        time: now,
        latitude: 12.9763 + n * .0001,
        longitude: 77.5929,
        accuracy: 5,
        speed: 1,
      ),
    );
  }
  stderr.writeln('PROBE settling');
  await recorder.settled();
  stderr.writeln('PROBE pausing');
  await recorder.pause();
  stderr.writeln('PROBE ready');
  final paused = recorder.state as Paused;
  stdout.writeln('PAUSED_READY $id ${paused.journey.uuid}');
  await Completer<void>().future;
}
