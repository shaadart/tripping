import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../history/journey_history.dart';
import 'format.dart';

/// Writes [past] as a GPX file and offers it through Android's share sheet.
/// The file holds location history, so it is deleted once handed over (the
/// share plugin keeps its own copy for the receiving app).
Future<void> shareGpx(JourneyHistory history, PastJourney past) async {
  final journey = past.journey;
  final local = journey.createdAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
  final name = '${modeName(journey.mode)} $stamp';
  final file = File(
    '${(await getTemporaryDirectory()).path}/tripping-'
    '${stamp.replaceAll(RegExp('[ :]'), '-')}-${journey.mode.name}.gpx',
  );
  try {
    await file.writeAsString(await history.gpxOf(past, name: name));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/gpx+xml')],
        subject: name,
      ),
    );
  } finally {
    if (file.existsSync()) await file.delete();
  }
}
