import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../app/theme.dart';
import 'download_style.dart';
import 'map_tiles.dart';
import 'offline_area.dart';

/// An area kept on the phone for use without a connection.
class OfflineMap {
  const OfflineMap({
    required this.id,
    required this.name,
    required this.area,
    required this.release,
    required this.savedAt,
    required this.bytes,
    required this.complete,
    required this.progress,
    this.terrain = false,
  });

  final int id;
  final String name;
  final Area area;

  /// The tile release it holds (see [MapTiles]).
  final String? release;
  final DateTime? savedAt;
  final int bytes;
  final bool complete;

  /// 0 to 1 while incomplete.
  final double progress;

  /// Whether it holds terrain for hill shading (areas saved before O3 do
  /// not).
  final bool terrain;

  /// Complete, with terrain, from the [newest] map data: nothing to update.
  bool isCurrent(String newest) => release == newest && complete && terrain;
}

/// Why a download did not go ahead.
class OfflineMapError implements Exception {
  const OfflineMapError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Offline areas: list, download, update and delete.
abstract interface class OfflineMaps {
  /// The saved areas as last listed, kept current after every change.
  ValueListenable<List<OfflineMap>> get saved;

  Future<List<OfflineMap>> list();

  /// The newest map data release, or null without a connection.
  Future<String?> newestRelease();

  /// Downloads [area] as [name], reporting progress from 0 to 1. Fails with
  /// an [OfflineMapError] when the area is too big, there is no connection,
  /// or saved areas hold older map data (see [updateAll]).
  Stream<double> download(String name, Area area);

  /// Downloads every saved area again from the newest release, then moves
  /// the maps to it and removes the old copies. If any download fails,
  /// nothing changes: the old areas stay and the maps keep their release.
  Stream<double> updateAll();

  Future<void> delete(int id);
}

/// Offline areas kept by MapLibre, downloaded within OpenFreeMap's terms:
/// at most [OfflineLimits.tiles] tiles and [OfflineLimits.bytes] each, four
/// requests at a time (set at startup), one area at a time.
class MapLibreOfflineMaps implements OfflineMaps {
  MapLibreOfflineMaps(this._tiles);

  final MapTiles _tiles;
  final _saved = ValueNotifier<List<OfflineMap>>(const []);

  /// How long a download may take to report anything at all.
  static const _startWithin = Duration(seconds: 30);

  @override
  ValueListenable<List<OfflineMap>> get saved => _saved;

  @override
  Future<List<OfflineMap>> list() async {
    final areas = [
      for (final region in await maplibre.getListOfRegions())
        await _describe(region),
    ];
    _saved.value = areas;
    return areas;
  }

  Future<OfflineMap> _describe(maplibre.OfflineRegion region) async {
    final status = await maplibre.getOfflineRegionStatus(region.id);
    final bounds = region.definition.bounds;
    final metadata = region.metadata;
    return OfflineMap(
      id: region.id,
      name: metadata['name'] as String? ?? 'Offline area',
      area: (
        south: bounds.southwest.latitude,
        west: bounds.southwest.longitude,
        north: bounds.northeast.latitude,
        east: bounds.northeast.longitude,
      ),
      release: metadata['release'] as String?,
      savedAt: switch (metadata['savedAt']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
      bytes: status.completedResourceSize,
      complete: status.isComplete,
      terrain: metadata['terrain'] == true,
      // Reported as a percentage.
      progress: (status.downloadProgress / 100).clamp(0, 1).toDouble(),
    );
  }

  @override
  Future<String?> newestRelease() => MapTiles.latest();

  @override
  Stream<double> download(String name, Area area) => _stream((progress) async {
    if (!fitsOneDownload(area)) {
      throw OfflineMapError(
        'This area needs about ${tilesFor(area)} map tiles; one download '
        'can hold ${OfflineLimits.tiles} tiles or 50 MB. Zoom in to a '
        'smaller area.',
      );
    }
    // The download's tiles come from the newest release (the hosted style
    // follows the index), so the maps must be pinned to that release too.
    final newest = await _newest();
    if (_tiles.release != newest) {
      if ((await list()).isNotEmpty) {
        throw const OfflineMapError(
          'Newer map data has come out since your saved areas were '
          'downloaded. Use "Update all" first, so every area matches.',
        );
      }
      await _tiles.pin(newest);
    }
    await _fetch(name, area, newest, progress);
    await list();
  });

  @override
  Stream<double> updateAll() => _stream((progress) async {
    final newest = await _newest();
    final old = [
      for (final saved in await list())
        if (!saved.isCurrent(newest)) saved,
    ];
    final made = <int>[];
    try {
      for (final (i, saved) in old.indexed) {
        made.add(
          await _fetch(
            saved.name,
            saved.area,
            newest,
            (p) => progress((i + p) / old.length),
          ),
        );
      }
    } on Object {
      // All or nothing: the old areas and the maps' release stay.
      for (final id in made) {
        await maplibre.deleteOfflineRegion(id);
      }
      await list();
      rethrow;
    }
    await _tiles.pin(newest);
    for (final saved in old) {
      await maplibre.deleteOfflineRegion(saved.id);
    }
    await list();
  });

  @override
  Future<void> delete(int id) async {
    await maplibre.deleteOfflineRegion(id);
    await list();
  }

  Future<String> _newest() async =>
      await MapTiles.latest() ??
      (throw const OfflineMapError(
        'Downloading needs an internet connection.',
      ));

  /// Runs [work] as a progress stream ending in 1, or in an
  /// [OfflineMapError].
  Stream<double> _stream(
    Future<void> Function(void Function(double) progress) work,
  ) {
    final out = StreamController<double>();
    unawaited(() async {
      try {
        await work((p) {
          if (!out.isClosed) out.add(p.clamp(0, 1));
        });
        out.add(1);
      } on OfflineMapError catch (error) {
        out.addError(error);
      } on Object catch (error) {
        out.addError(OfflineMapError('The download failed: $error'));
      } finally {
        await out.close();
      }
    }());
    return out.stream;
  }

  /// Downloads one area from [release] and returns its id once complete.
  /// On any failure the half-made area is removed and an [OfflineMapError]
  /// thrown.
  Future<int> _fetch(
    String name,
    Area area,
    String release,
    void Function(double) onProgress,
  ) async => withLocalStyle(
    // The light look's style: OpenFreeMap's index, fonts and sprites, as
    // every look uses, and the terrain source.
    await rootBundle.loadString(mapAsset(Look.light)),
    (style) => _fetchWith(style, name, area, release, onProgress),
  );

  Future<int> _fetchWith(
    String style,
    String name,
    Area area,
    String release,
    void Function(double) onProgress,
  ) async {
    // OpenFreeMap's 50 MB is for its own data; terrain comes on top.
    final allowed =
        OfflineLimits.bytes + 2 * estimatedTerrainBytes(terrainTilesFor(area));
    final done = Completer<void>();
    void fail(String message) {
      if (!done.isCompleted) done.completeError(OfflineMapError(message));
    }

    // MapLibre gives no event at all while it cannot even start (for one,
    // it fetched no style); a download must never sit at 0 % forever.
    final stalled = Timer(
      _startWithin,
      () => fail(
        "The download didn't start. Check the internet connection and try "
        'again.',
      ),
    );
    final region = await maplibre.downloadOfflineRegion(
      maplibre.OfflineRegionDefinition(
        bounds: maplibre.LatLngBounds(
          southwest: maplibre.LatLng(area.south, area.west),
          northeast: maplibre.LatLng(area.north, area.east),
        ),
        // Served locally (MapLibre's downloader cannot read a file). Its
        // tiles follow OpenFreeMap's index, so they are the newest
        // release's; all looks share tiles, fonts, sprites and terrain, so
        // one download serves every look.
        mapStyleUrl: style,
        minZoom: 0,
        maxZoom: OfflineLimits.maxZoom.toDouble(),
      ),
      metadata: {
        'name': name,
        'release': release,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'terrain': true,
      },
      onEvent: (event) {
        stalled.cancel();
        switch (event) {
          case maplibre.InProgress(
            :final progress,
            :final completedResourceSize,
          ):
            if (completedResourceSize > allowed) {
              fail('This area is larger than 50 MB; choose a smaller one.');
            } else {
              // Reported as a percentage.
              onProgress(progress / 100);
            }
          case maplibre.Success():
            if (!done.isCompleted) done.complete();
          case maplibre.Error(:final cause):
            fail(cause.message ?? 'The download failed.');
        }
      },
    );
    try {
      await done.future;
      return region.id;
    } on Object {
      stalled.cancel();
      await maplibre.deleteOfflineRegion(region.id);
      rethrow;
    }
  }
}
