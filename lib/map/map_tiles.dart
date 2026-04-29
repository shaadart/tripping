import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../app/settings.dart';
import '../app/theme.dart';
import '../net/http.dart';

/// Which OpenFreeMap tile release the maps draw and download, and the style
/// files that point at it.
///
/// OpenFreeMap publishes a tile release about weekly. Its index, which names
/// the current release, is cached for an hour, while a release's tiles never
/// change. An offline area holds the tiles of one release, so if the maps
/// followed the index, a downloaded area would silently stop matching a
/// week later. The maps therefore draw a pinned release, written into style
/// files as explicit tile addresses, and the pin moves only when no offline
/// area depends on it (D-026).
class MapTiles {
  MapTiles._(this._root, this._settings);

  /// The instance the maps use; null in tests, where styles come from the
  /// bundled assets.
  static MapTiles? current;

  static const index = 'https://tiles.openfreemap.org/planet';

  /// Identifies the app to the tile server, as its terms ask.
  static const userAgent = appUserAgent;

  final Directory _root;
  final Settings _settings;

  /// The pinned release, or null before the index was ever read.
  String? get release => _settings.tileRelease.value;

  /// Writes the style files for the pinned release, if any.
  static Future<MapTiles> open(Directory documents, Settings settings) async {
    final tiles = MapTiles._(Directory('${documents.path}/map'), settings);
    await tiles._writeStyles(settings.tileRelease.value);
    return tiles;
  }

  /// The style file for [look]. maplibre_gl loads an absolute path as a file;
  /// offline downloads take it as a `file://` address.
  String stylePath(Look look) => '${_dir(release).path}/${look.name}.json';

  Directory _dir(String? release) =>
      Directory('${_root.path}/${release ?? 'index'}');

  /// Test builds only (`--dart-define=TRIPPING_PRETEND_RELEASE=<release>`):
  /// treat an older, still-served release as the newest, to exercise
  /// "update all" on a device without waiting a week. Empty in normal
  /// builds.
  static const _pretend = String.fromEnvironment('TRIPPING_PRETEND_RELEASE');

  /// The newest release named by the index, or null without a connection.
  static Future<String?> latest({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_pretend.isNotEmpty) return _pretend;
    final client = HttpClient()
      ..userAgent = userAgent
      ..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(index)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join();
      return releaseFromIndex(jsonDecode(body));
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Whether [release]'s tiles are still served: false once withdrawn,
  /// null when it cannot be told (no connection).
  static Future<bool?> served(
    String release, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()
      ..userAgent = userAgent
      ..connectionTimeout = timeout;
    try {
      final request = await client
          .headUrl(Uri.parse('$index/$release/0/0/0.pbf'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      return switch (response.statusCode) {
        HttpStatus.ok => true,
        HttpStatus.notFound || HttpStatus.gone => false,
        _ => null,
      };
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Follows the newest release when nothing on the phone depends on the
  /// pinned one, or when the pinned one is no longer served. [hasOfflineMaps]
  /// says whether offline areas hold the pinned release.
  /// The network checks default to [latest] and [served].
  Future<void> settle({
    required Future<bool> Function() hasOfflineMaps,
    Future<String?> Function() newest = latest,
    Future<bool?> Function(String release) isServed = served,
  }) async {
    final next = await newest();
    final pinned = release;
    if (next == null || next == pinned) return;
    if (pinned == null ||
        !await hasOfflineMaps() ||
        await isServed(pinned) == false) {
      await pin(next);
    }
  }

  /// Moves the pin to [release] and writes its styles.
  Future<void> pin(String release) async {
    await _writeStyles(release);
    await _settings.setTileRelease(release);
  }

  Future<void> _writeStyles(String? release) async {
    final dir = _dir(release);
    await dir.create(recursive: true);
    for (final look in Look.values) {
      final style = await rootBundle.loadString(mapAsset(look));
      await File(
        '${dir.path}/${look.name}.json',
      ).writeAsString(pinnedStyle(style, release));
    }
  }
}

final _releaseInAddress = RegExp(r'/planet/([^/]+)/\{z\}/');

/// The release in an index's tile address, such as `20261025_080012_pt`.
String? releaseFromIndex(Object? index) {
  if (index is! Map) return null;
  final tiles = index['tiles'];
  if (tiles is! List || tiles.isEmpty || tiles.first is! String) return null;
  return _releaseInAddress.firstMatch(tiles.first as String)?.group(1);
}

/// [style] with its OpenFreeMap source drawing [release] by explicit tile
/// address; unchanged when [release] is null.
String pinnedStyle(String style, String? release) {
  if (release == null) return style;
  final json = jsonDecode(style) as Map<String, Object?>;
  final sources = json['sources']! as Map<String, Object?>;
  sources['openmaptiles'] = {
    'type': 'vector',
    'tiles': ['${MapTiles.index}/$release/{z}/{x}/{y}.pbf'],
    'minzoom': 0,
    'maxzoom': 14,
    // The index used to supply this; with explicit tiles the style must.
    'attribution':
        '<a href="https://openfreemap.org" target="_blank">OpenFreeMap</a> '
        '<a href="https://www.openmaptiles.org/" target="_blank">'
        '&copy; OpenMapTiles</a> Data from '
        '<a href="https://www.openstreetmap.org/copyright" target="_blank">'
        'OpenStreetMap</a>',
  };
  return jsonEncode(json);
}
