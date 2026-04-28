// Feeds a simulated walk or drive into a phone's GPS over adb, through
// Android's test location provider, so recording and the map can be tested at
// a desk. The route loops around Cubbon Park, Bengaluru (a public place).
//
//   dart run tool/simulate_route.dart [--minutes 5] [--speed 1.4]
//       [--accuracy 5] [--serial 5C231XEBF9B8BD]
//
// While it runs, the phone's real GPS and network location are replaced
// (fused location blends both, so faking only GPS could leak the phone's real
// position). Both are always restored at the end, also on Ctrl-C.
import 'dart:async';
import 'dart:io';
import 'dart:math';

const _origin = (lat: 12.9763, lon: 77.5929);
// The loop: _east metres east, _north metres north, and back.
const _east = 300.0;
const _north = 200.0;
const _earthRadius = 6371008.8;
const _providers = ['gps', 'network'];

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final minutes = double.parse(option('minutes', '5'));
  final speed = double.parse(option('speed', '1.4'));
  final accuracy = double.parse(option('accuracy', '5'));
  final serial = option('serial', '5C231XEBF9B8BD');

  Future<void> adb(List<String> command) async {
    final result = await Process.run('adb', [
      '-s',
      serial,
      'shell',
      ...command,
    ]);
    if (result.exitCode != 0) {
      throw StateError('adb ${command.join(' ')}: ${result.stderr}');
    }
  }

  Future<void> restore() async {
    for (final provider in _providers) {
      await adb([
        'cmd',
        'location',
        'providers',
        'remove-test-provider',
        provider,
      ]).catchError((Object _) {});
    }
    await adb([
      'appops',
      'set',
      'com.android.shell',
      'android:mock_location',
      'default',
    ]).catchError((Object _) {});
    stdout.writeln('Real GPS restored.');
  }

  final interrupted = ProcessSignal.sigint.watch().listen((_) async {
    await restore();
    exit(130);
  });

  final random = Random(1);
  double noise() =>
      sqrt(-2 * log(1 - random.nextDouble())) *
      cos(2 * pi * random.nextDouble());

  try {
    await adb([
      'appops',
      'set',
      'com.android.shell',
      'android:mock_location',
      'allow',
    ]);
    for (final provider in _providers) {
      await adb([
        'cmd',
        'location',
        'providers',
        'add-test-provider',
        provider,
        '--supportsAltitude',
        '--supportsSpeed',
        '--supportsBearing',
      ]);
      await adb([
        'cmd',
        'location',
        'providers',
        'set-test-provider-enabled',
        provider,
        'true',
      ]);
    }

    const perimeter = 2 * (_east + _north);
    final steps = (minutes * 60).round();
    for (var second = 0; second < steps; second++) {
      // Position along the rectangular loop, anticlockwise from the origin.
      final along = (speed * second) % perimeter;
      final (east, north) = along < _east
          ? (along, 0.0)
          : along < _east + _north
          ? (_east, along - _east)
          : along < 2 * _east + _north
          ? (2 * _east + _north - along, _north)
          : (0.0, perimeter - along);
      final sigma = accuracy / 1.51;
      final lat =
          _origin.lat + (north + sigma * noise()) / _earthRadius * 180 / pi;
      final lon =
          _origin.lon +
          (east + sigma * noise()) /
              (_earthRadius * cos(_origin.lat * pi / 180)) *
              180 /
              pi;
      for (final provider in _providers) {
        await adb([
          'cmd',
          'location',
          'providers',
          'set-test-provider-location',
          provider,
          '--location',
          '${lat.toStringAsFixed(7)},${lon.toStringAsFixed(7)}',
          '--accuracy',
          accuracy.toStringAsFixed(1),
        ]);
      }
      if (second % 30 == 0) {
        stdout.writeln(
          '${second ~/ 60}:${(second % 60).toString().padLeft(2, '0')} '
          '${(speed * second).round()} m simulated',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } finally {
    await interrupted.cancel();
    await restore();
  }
}
