import 'dart:async';

import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

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
}

/// Why a download did not go ahead.
class OfflineMapError implements Exception {
  const OfflineMapError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Offline areas: list, download and delete.
abstract interface class OfflineMaps {
  Future<List<OfflineMap>> list();

  /// Downloads [area] as [name], reporting progress from 0 to 1. Throws an
  /// [OfflineMapError] when the area is too big or there is no connection.
  Stream<double> download(String name, Area area);

  Future<void> delete(int id);
}

/// Offline areas kept by MapLibre, downloaded within OpenFreeMap's terms:
/// at most [OfflineLimits.tiles] tiles and [OfflineLimits.bytes] each, four
/// requests at a time (set at startup), from the pinned tile release.
class MapLibreOfflineMaps implements OfflineMaps {
  MapLibreOfflineMaps(this._tiles);

  final MapTiles _tiles;

  @override
  Future<List<OfflineMap>> list() async => [
    for (final region in await maplibre.getListOfRegions())
      await _describe(region),
  ];

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
      // Reported as a percentage.
      progress: (status.downloadProgress / 100).clamp(0, 1).toDouble(),
    );
  }

  @override
  Stream<double> download(String name, Area area) {
    final controller = StreamController<double>();
    unawaited(_download(name, area, controller));
    return controller.stream;
  }

  Future<void> _download(
    String name,
    Area area,
    StreamController<double> out,
  ) async {
    try {
      if (!fitsOneDownload(area)) {
        throw OfflineMapError(
          'This area needs about ${tilesFor(area)} map tiles; one download '
          'can hold ${OfflineLimits.tiles} tiles or 50 MB. Zoom in to a '
          'smaller area.',
        );
      }
      // The download's tiles come from the newest release (the hosted style
      // follows the index), so the maps must be pinned to that release too.
      final newest = await MapTiles.latest();
      if (newest == null) {
        throw const OfflineMapError(
          'Downloading needs an internet connection.',
        );
      }
      if (_tiles.release != newest) {
        if ((await list()).isNotEmpty) {
          throw const OfflineMapError(
            'Newer map data has come out since your saved areas were '
            'downloaded. Delete them and download them again before adding '
            'another area, so all of them match.',
          );
        }
        await _tiles.pin(newest);
      }
      final release = newest;
      // MapLibre gives no event at all while it cannot even start (for one,
      // it fetched no style); a download must never sit at 0 % forever.
      final stalled = Timer(_startWithin, () {
        _fail(
          out,
          "The download didn't start. Check the internet connection and "
          'try again.',
        );
      });
      final region = await maplibre.downloadOfflineRegion(
        maplibre.OfflineRegionDefinition(
          bounds: maplibre.LatLngBounds(
            southwest: maplibre.LatLng(area.south, area.west),
            northeast: maplibre.LatLng(area.north, area.east),
          ),
          // OpenFreeMap's own Positron: MapLibre's downloader fetches the
          // style over the network (it could not read our style files). It
          // has every font the looks use, and all share tiles and sprites,
          // so one download serves every look.
          mapStyleUrl: MapTiles.downloadStyle,
          minZoom: 0,
          maxZoom: OfflineLimits.maxZoom.toDouble(),
        ),
        metadata: {
          'name': name,
          'release': release,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
        },
        onEvent: (event) async {
          stalled.cancel();
          switch (event) {
            case maplibre.InProgress(
              :final progress,
              :final completedResourceSize,
            ):
              if (completedResourceSize > OfflineLimits.bytes) {
                _fail(
                  out,
                  'This area is larger than 50 MB; choose a smaller one.',
                );
                return;
              }
              if (!out.isClosed) out.add((progress / 100).clamp(0, 1));
            case maplibre.Success():
              if (!out.isClosed) {
                out.add(1);
                await out.close();
              }
            case maplibre.Error(:final cause):
              _fail(out, cause.message ?? 'The download failed.');
          }
        },
      );
      _regionOf[out] = region.id;
    } on OfflineMapError catch (error) {
      out.addError(error);
      await out.close();
    } on Object catch (error) {
      out.addError(OfflineMapError('The download failed: $error'));
      await out.close();
    }
  }

  /// How long a download may take to report anything at all.
  static const _startWithin = Duration(seconds: 30);

  /// The region each running download writes to, so a failed one can be
  /// removed rather than left half-made.
  final _regionOf = <StreamController<double>, int>{};

  void _fail(StreamController<double> out, String message) {
    if (out.isClosed) return;
    out.addError(OfflineMapError(message));
    unawaited(out.close());
    final id = _regionOf.remove(out);
    if (id != null) unawaited(delete(id));
  }

  @override
  Future<void> delete(int id) async {
    await maplibre.deleteOfflineRegion(id);
  }
}
