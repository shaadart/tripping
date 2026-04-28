import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/map/map_tiles.dart';

void main() {
  group('releaseFromIndex', () {
    test('reads the release from the tile address', () {
      expect(
        releaseFromIndex({
          'tiles': [
            'https://tiles.openfreemap.org/planet/20261025_080012_pt/{z}/{x}/{y}.pbf',
          ],
        }),
        '20261025_080012_pt',
      );
    });

    test('anything unexpected is no release, not a guess', () {
      expect(releaseFromIndex(null), isNull);
      expect(releaseFromIndex({'tiles': <String>[]}), isNull);
      expect(
        releaseFromIndex({
          'tiles': ['https://example.com/{z}/{x}/{y}.pbf'],
        }),
        isNull,
      );
    });
  });

  group('pinnedStyle', () {
    const style =
        '{"version":8,"sources":{"openmaptiles":{"type":"vector",'
        '"url":"https://tiles.openfreemap.org/planet"},"other":{"type":"raster"}},'
        '"layers":[{"id":"background","type":"background"}]}';

    test('without a release the style is left as it is', () {
      expect(pinnedStyle(style, null), style);
    });

    test('a release becomes explicit tile addresses, with attribution', () {
      final pinned =
          jsonDecode(pinnedStyle(style, '20261025_080012_pt'))
              as Map<String, Object?>;
      final sources = pinned['sources']! as Map<String, Object?>;
      final source = sources['openmaptiles']! as Map<String, Object?>;
      expect(source['tiles'], [
        'https://tiles.openfreemap.org/planet/20261025_080012_pt/{z}/{x}/{y}.pbf',
      ]);
      expect(source.containsKey('url'), isFalse);
      expect(source['maxzoom'], 14);
      expect(source['attribution'] as String, contains('OpenStreetMap'));
      // Everything else is untouched.
      expect(sources['other'], {'type': 'raster'});
      expect(pinned['layers'], hasLength(1));
    });
  });

  group('settle', () {
    late Directory dir;
    late Settings settings;
    late MapTiles tiles;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      dir = Directory.systemTemp.createTempSync('tripping_tiles');
      settings = await Settings.open(File('${dir.path}/settings.json'));
      tiles = await MapTiles.open(dir, settings);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<String?> newest() async => 'r2';

    test('the first release read is pinned, and its styles written', () async {
      expect(tiles.release, isNull);
      await tiles.settle(hasOfflineMaps: () async => false, newest: newest);
      expect(tiles.release, 'r2');
      expect(
        (await Settings.open(
          File('${dir.path}/settings.json'),
        )).tileRelease.value,
        'r2',
      );
      final style = File(tiles.stylePath(Look.dark)).readAsStringSync();
      expect(style, contains('/planet/r2/{z}/{x}/{y}.pbf'));
    });

    test('offline maps keep the pin while their release is served', () async {
      await tiles.pin('r1');
      await tiles.settle(
        hasOfflineMaps: () async => true,
        newest: newest,
        isServed: (_) async => true,
      );
      expect(tiles.release, 'r1');
    });

    test('a withdrawn release is left, offline maps or not', () async {
      await tiles.pin('r1');
      await tiles.settle(
        hasOfflineMaps: () async => true,
        newest: newest,
        isServed: (_) async => false,
      );
      expect(tiles.release, 'r2');
    });

    test('without offline maps the newest release is followed', () async {
      await tiles.pin('r1');
      await tiles.settle(hasOfflineMaps: () async => false, newest: newest);
      expect(tiles.release, 'r2');
    });

    test('without a connection nothing changes', () async {
      await tiles.pin('r1');
      await tiles.settle(
        hasOfflineMaps: () async => false,
        newest: () async => null,
      );
      expect(tiles.release, 'r1');
    });
  });
}
