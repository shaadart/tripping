import 'dart:math';

/// What one offline download may hold under OpenFreeMap's terms: at most
/// 3,000 tiles or 50 MB, fetched with at most 4 parallel requests by an
/// app that names itself (openfreemap.org/tos, checked 2026-10-28).
abstract final class OfflineLimits {
  static const tiles = 3000;
  static const bytes = 50 * 1024 * 1024;
  static const parallelRequests = 4;

  /// The vector tiles stop at zoom 14; closer views draw these larger.
  static const maxZoom = 14;
}

/// A box to keep offline, in degrees.
typedef Area = ({double south, double west, double north, double east});

/// Vector tiles needed to cover [area] at every zoom from 0 to
/// [OfflineLimits.maxZoom]: the size of a download before it starts.
int tilesFor(Area area, {int maxZoom = OfflineLimits.maxZoom}) {
  var total = 0;
  for (var z = 0; z <= maxZoom; z++) {
    final n = 1 << z;
    int column(double longitude) =>
        ((longitude + 180) / 360 * n).floor().clamp(0, n - 1);
    int row(double latitude) {
      final phi = latitude.clamp(-85.0511, 85.0511) * pi / 180;
      return ((1 - log(tan(phi) + 1 / cos(phi)) / pi) / 2 * n).floor().clamp(
        0,
        n - 1,
      );
    }

    final columns = column(area.east) - column(area.west) + 1;
    final rows = row(area.south) - row(area.north) + 1;
    total += columns * rows;
  }
  return total;
}

/// Fonts and map imagery every area includes: about 8.5 MB, measured on
/// the Pixel (E-023: 109 tiles came to 10.1 MB).
const _sharedBytes = 8704 * 1024;

/// A rough size: the shared fonts and imagery, plus vector tiles averaging
/// about 15 KB, more in cities and less in open country. Shown as an
/// estimate, never as a promise; the download itself stops past 50 MB.
int estimatedBytes(int tiles) => _sharedBytes + tiles * 15 * 1024;

/// Whether [area] fits in one download, by tiles and by estimated size.
bool fitsOneDownload(Area area) {
  final tiles = tilesFor(area);
  return tiles <= OfflineLimits.tiles &&
      estimatedBytes(tiles) <= OfflineLimits.bytes;
}

/// Whether the point lies inside [area].
bool covers(Area area, double latitude, double longitude) =>
    latitude >= area.south &&
    latitude <= area.north &&
    longitude >= area.west &&
    longitude <= area.east;
