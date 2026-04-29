import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/map/offline_area.dart';

// Around Bengaluru: 0.27° of latitude, 0.28° of longitude.
const city = (south: 12.84, west: 77.45, north: 13.11, east: 77.73);

void main() {
  test('the whole world is one tile at zoom 0, four at zoom 1', () {
    const world = (south: -85.0, west: -180.0, north: 85.0, east: 179.999);
    expect(tilesFor(world, maxZoom: 0), 1);
    expect(tilesFor(world, maxZoom: 1), 1 + 4);
  });

  test('a city fits easily: about 230 tiles for 30 × 30 km', () {
    final tiles = tilesFor(city);
    expect(tiles, inInclusiveRange(150, 400));
    expect(fitsOneDownload(city), isTrue);
  });

  test('a whole state does not fit in one download', () {
    const state = (south: 11.5, west: 74.0, north: 18.5, east: 78.6);
    expect(tilesFor(state), greaterThan(OfflineLimits.tiles));
    expect(fitsOneDownload(state), isFalse);
  });

  test('every zoom counts at least the one tile under the area', () {
    const spot = (south: 12.97, west: 77.59, north: 12.9701, east: 77.5901);
    expect(tilesFor(spot), OfflineLimits.maxZoom + 1);
  });

  test('the size estimate includes fonts and imagery every area needs', () {
    // Measured: 109 tiles came to 10.1 MB on the Pixel.
    expect(estimatedBytes(109) / (1024 * 1024), closeTo(10.1, 0.5));
    expect(estimatedBytes(200), greaterThan(estimatedBytes(100)));
  });

  test('an area must fit both limits: tiles and about 50 MB', () {
    // 2,900 tiles is under the tile limit but over 50 MB by estimate.
    expect(estimatedBytes(2900), greaterThan(OfflineLimits.bytes));
  });

  test('an area covers the points inside it, edges included', () {
    expect(covers(city, 12.97, 77.59), isTrue);
    expect(covers(city, 12.84, 77.45), isTrue);
    expect(covers(city, 13.2, 77.59), isFalse);
    expect(covers(city, 12.97, 77.8), isFalse);
  });

  test('terrain comes from zoom 3 to 12, a small share of the map tiles', () {
    final terrain = terrainTilesFor(city);
    expect(terrain, tilesFor(city, maxZoom: 12) - tilesFor(city, maxZoom: 2));
    expect(terrain, lessThan(tilesFor(city) / 3));
    expect(
      estimatedAreaBytes(city),
      estimatedBytes(tilesFor(city)) + estimatedTerrainBytes(terrain),
    );
  });
}
