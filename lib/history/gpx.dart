import '../journey/journey.dart';
import '../journey/journey_store.dart';

/// A journey as GPX 1.1: its waypoints, then one track with one `trkseg` per
/// recorded segment, so other apps don't join what Tripping never joined
/// either.
///
/// Only what was measured is written: position, altitude and time. GPX has
/// no field for a fix's accuracy in metres (`hdop` is a unitless dilution),
/// so accuracy is left out rather than misfiled.
String gpxOf({
  required String name,
  required JourneyMode mode,
  required DateTime startedAt,
  required List<List<Fix>> track,
  List<WaypointRow> waypoints = const [],
}) {
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<gpx version="1.1" creator="Tripping" '
      'xmlns="http://www.topografix.com/GPX/1/1" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
      'http://www.topografix.com/GPX/1/1/gpx.xsd">',
    )
    ..writeln('  <metadata>')
    ..writeln('    <name>${_escape(name)}</name>')
    ..writeln('    <time>${_time(startedAt)}</time>')
    ..writeln('  </metadata>');
  // GPX wants waypoints before the track. A marked one carries the time of
  // the fix it came from; a planned one, when it was planned.
  for (final waypoint in waypoints) {
    out
      ..write(
        '  <wpt lat="${waypoint.latitude.toStringAsFixed(7)}" '
        'lon="${waypoint.longitude.toStringAsFixed(7)}">',
      )
      ..write(switch (waypoint.altitude) {
        final altitude? => '<ele>${altitude.toStringAsFixed(1)}</ele>',
        null => '',
      })
      ..write('<time>${_time(waypoint.fixTime ?? waypoint.createdAt)}</time>')
      ..write(switch (waypoint.name) {
        final name? => '<name>${_escape(name)}</name>',
        null => '',
      })
      ..write(switch (waypoint.note) {
        final note? => '<desc>${_escape(note)}</desc>',
        null => '',
      })
      ..writeln('<type>${waypoint.kind.name}</type></wpt>');
  }
  out
    ..writeln('  <trk>')
    ..writeln('    <name>${_escape(name)}</name>')
    ..writeln('    <type>${mode.name}</type>');
  for (final segment in track) {
    if (segment.isEmpty) continue;
    out.writeln('    <trkseg>');
    for (final fix in segment) {
      out.write(
        '      <trkpt lat="${fix.latitude.toStringAsFixed(7)}" '
        'lon="${fix.longitude.toStringAsFixed(7)}">',
      );
      if (fix.altitude case final altitude?) {
        out.write('<ele>${altitude.toStringAsFixed(1)}</ele>');
      }
      out.writeln('<time>${_time(fix.time)}</time></trkpt>');
    }
    out.writeln('    </trkseg>');
  }
  out
    ..writeln('  </trk>')
    ..writeln('</gpx>');
  return out.toString();
}

String _time(DateTime time) => time.toUtc().toIso8601String();

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
