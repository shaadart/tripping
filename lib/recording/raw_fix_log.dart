import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../journey/journey.dart';
import 'location_source.dart';

/// Debug aid: writes every fix the platform delivers, kept or not, as JSON
/// lines, so the distance rules can be retuned on real traces (R4).
///
/// The file is location history. Wire it in debug builds only; it never
/// leaves the phone unless pulled over adb.
class RawFixLog implements LocationSource {
  RawFixLog(this._inner, this._file);

  final LocationSource _inner;
  final File _file;

  @override
  Future<LocationAccess> requestAccess() => _inner.requestAccess();

  @override
  Future<void> openSettingsFor(LocationAccess problem) =>
      _inner.openSettingsFor(problem);

  @override
  Future<Fix?> lastKnown() => _inner.lastKnown();

  @override
  Stream<Fix> watch(JourneyMode mode) {
    _write({'event': 'watch', 'mode': mode.name, 'at': _now()});
    return _inner
        .watch(mode)
        .transform(
          StreamTransformer.fromHandlers(
            handleData: (fix, sink) {
              _write({
                'event': 'fix',
                'arrived': _now(),
                'time': fix.time.toIso8601String(),
                'lat': fix.latitude,
                'lon': fix.longitude,
                'accuracy': fix.accuracy,
                'altitude': fix.altitude,
                'altitudeAccuracy': fix.altitudeAccuracy,
                'speed': fix.speed,
                'heading': fix.heading,
              });
              sink.add(fix);
            },
            handleError: (error, stackTrace, sink) {
              _write({'event': 'error', 'at': _now(), 'error': '$error'});
              sink.addError(error, stackTrace);
            },
          ),
        );
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  void _write(Map<String, Object?> line) =>
      _file.writeAsStringSync('${jsonEncode(line)}\n', mode: FileMode.append);
}
