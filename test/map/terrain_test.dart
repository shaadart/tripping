import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/map/terrain.dart';

void main() {
  test('each style draws hills at the strength the app assumes', () {
    for (final MapEntry(key: look, value: strength)
        in terrainExaggeration.entries) {
      final style =
          jsonDecode(File('assets/map/$look.json').readAsStringSync()) as Map;
      final hillshade = (style['layers'] as List).singleWhere(
        (layer) => (layer as Map)['id'] == 'hillshade',
      );
      expect(
        (hillshade as Map)['paint']['hillshade-exaggeration'],
        strength,
        reason: look,
      );
      expect((style['sources'] as Map)['terrain']['type'], 'raster-dem');
    }
  });

  test('stronger on an expedition, lighter on the road, in every look', () {
    expect(terrainShading('light', null), 0.35);
    expect(terrainShading('dark', JourneyMode.expedition), 0.65);
    for (final look in terrainExaggeration.keys) {
      final idle = terrainShading(look, null);
      expect(terrainShading(look, JourneyMode.expedition), greaterThan(idle));
      expect(terrainShading(look, JourneyMode.road), lessThan(idle));
      expect(
        terrainShading(look, JourneyMode.expedition),
        lessThanOrEqualTo(1),
      );
    }
  });
}
