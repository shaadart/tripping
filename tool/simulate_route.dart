// Feeds a simulated walk or drive into a phone's GPS over adb, through
// Android's test location provider, so recording and the map can be tested at
// a desk. By default the route loops around Cubbon Park, Bengaluru (a public
// place).
//
//   dart run tool/simulate_route.dart [--minutes 5] [--speed 1.4]
//       [--accuracy 5] [--serial 5C231XEBF9B8BD] [--origin 12.9763,77.5929]
//
// --origin moves the loop elsewhere; use only public places.
//
// While it runs, the phone's real GPS and network location are replaced
// (fused location blends both, so faking only GPS could leak the phone's real
// position). Both are restored at the end, on Ctrl-C and on SIGTERM. A
// SIGKILL cannot be caught: then run `dart run tool/simulate_route.dart
// --restore`, which only restores.
import 'dart:async';
import 'dart:io';
import 'dart:math';

const _cubbonPark = '12.9763,77.5929';
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
  final [originLat, originLon] = [
    for (final part in option('origin', _cubbonPark).split(','))
      double.parse(part),
  ];

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

  if (args.contains('--restore')) {
    await restore();
    return;
  }

  final stops = [
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
      signal.watch().listen((_) async {
        await restore();
        exit(130);
      }),
  ];

  final random = Random(1);
  double noise() =>
      sqrt(-2 * log(1 - random.nextDouble())) *
      cos(2 * pi * random.nextDouble());
  // Real GPS error wanders slowly rather than jumping every second: a
  // first-order Gauss–Markov process with a 30 s correlation time.
  final sigma = accuracy / 1.51;
  final keep = exp(-1 / 30);
  final fresh = sigma * sqrt(1 - keep * keep);
  var (errorEast, errorNorth) = (sigma * noise(), sigma * noise());

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
      errorEast = keep * errorEast + fresh * noise();
      errorNorth = keep * errorNorth + fresh * noise();
      final lat = originLat + (north + errorNorth) / _earthRadius * 180 / pi;
      final lon =
          originLon +
          (east + errorEast) /
              (_earthRadius * cos(originLat * pi / 180)) *
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
    for (final stop in stops) {
      await stop.cancel();
    }
    await restore();
  }
}
