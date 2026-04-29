import '../journey/journey.dart';

/// Hill-shading strength for each look's map style, as drawn by default
/// and between journeys. `tool/map_styles.dart` writes these into the
/// styles.
const terrainExaggeration = {'light': 0.35, 'dark': 0.5, 'sun': 0.25};

/// Strength on the road and on an expedition, per look, chosen on the
/// Pixel (E-029): stronger on an expedition, where the land is the map,
/// lighter on the road, where roads and labels matter more. Dark stops at
/// 0.65: above it, lit slopes turn into grey patches over the roads.
const _byMode = {
  'light': (road: 0.2, expedition: 0.55),
  'dark': (road: 0.3, expedition: 0.65),
  'sun': (road: 0.15, expedition: 0.4),
};

/// How strongly hills are shaded in [look] during a journey in [mode] (D2);
/// between journeys, the style's own strength.
double terrainShading(String look, JourneyMode? mode) {
  final byMode = _byMode[look] ?? _byMode['light']!;
  return switch (mode) {
    JourneyMode.expedition => byMode.expedition,
    JourneyMode.road => byMode.road,
    null => terrainExaggeration[look] ?? 0.35,
  };
}
