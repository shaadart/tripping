import 'dart:math';

import 'package:flutter/scheduler.dart';

/// Logs a summary of Flutter's frame timings once a minute, for measuring
/// jank on a device in profile or release builds. Only compiled in with
/// `--dart-define=TRIPPING_FRAME_STATS=true`; logs timings, never locations.
class FrameStats {
  static const enabled = bool.fromEnvironment('TRIPPING_FRAME_STATS');

  static final _build = <int>[];
  static final _raster = <int>[];
  static var _minute = 0;

  static void start() {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        _build.add(timing.buildDuration.inMicroseconds);
        _raster.add(timing.rasterDuration.inMicroseconds);
      }
    });
    Stream<void>.periodic(const Duration(minutes: 1)).listen((_) => _report());
  }

  static void _report() {
    _minute++;
    final frames = _build.length;
    String percentiles(List<int> micros) {
      if (micros.isEmpty) return '-';
      final sorted = [...micros]..sort();
      String at(double p) =>
          (sorted[min(sorted.length - 1, (p * sorted.length).floor())] / 1000)
              .toStringAsFixed(1);
      return 'p50 ${at(0.5)} p90 ${at(0.9)} p99 ${at(0.99)} max ${at(1)} ms';
    }

    // A frame misses a 60 Hz deadline when either thread takes over 16 ms.
    var slow = 0;
    for (var i = 0; i < frames; i++) {
      if (_build[i] > 16000 || _raster[i] > 16000) slow++;
    }
    // ignore: avoid_print
    print(
      'FRAME_STATS minute=$_minute frames=$frames slow=$slow '
      'build[${percentiles(_build)}] raster[${percentiles(_raster)}]',
    );
    _build.clear();
    _raster.clear();
  }
}
