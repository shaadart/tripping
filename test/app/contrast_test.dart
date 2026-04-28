import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/theme.dart';

/// WCAG 2 contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// The opaque fill colours a style paints under the track: background and
/// the large areas.
Map<String, Color> mapFills(String asset) {
  final style =
      jsonDecode(File(asset).readAsStringSync()) as Map<String, Object?>;
  final colours = <String, Color>{};
  for (final layer in (style['layers']! as List).cast<Map<String, Object?>>()) {
    final id = layer['id']! as String;
    if (!const {
      'background',
      'water',
      'landuse_residential',
      'landcover_wood',
      'park',
      'building',
    }.contains(id)) {
      continue;
    }
    final paint = layer['paint'] as Map<String, Object?>? ?? const {};
    final value = paint['background-color'] ?? paint['fill-color'];
    if (value is! String) continue;
    final m = RegExp(r'rgba\((\d+),(\d+),(\d+),').firstMatch(value);
    if (m == null) continue;
    colours[id] = Color.fromARGB(
      255,
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }
  return colours;
}

void main() {
  for (final look in Look.values) {
    group('${look.name} look', () {
      final theme = trippingLook(look);
      final scheme = theme.colorScheme;
      final extras = theme.extension<TrippingLook>()!;

      test('every text colour reads at 4.5:1 or better', () {
        final pairs = {
          'ink on surface': (scheme.onSurface, scheme.surface),
          'muted on surface': (scheme.onSurfaceVariant, scheme.surface),
          'button label': (scheme.onPrimary, scheme.primary),
          'ember text on surface': (scheme.primary, scheme.surface),
          'warning on surface': (extras.warning, scheme.surface),
        };
        for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
        }
      });

      test('the track stands out from the map at 3:1 or better', () {
        final fills = mapFills(extras.mapStyle);
        expect(fills, contains('background'));
        for (final MapEntry(key: name, value: fill) in fills.entries) {
          expect(
            contrast(scheme.primary, fill),
            greaterThanOrEqualTo(3),
            reason: 'track on $name',
          );
        }
      });
    });
  }

  test('high sun is the most legible look', () {
    double ink(Look look) {
      final scheme = trippingLook(look).colorScheme;
      return contrast(scheme.onSurface, scheme.surface);
    }

    expect(ink(Look.highSun), greaterThan(ink(Look.light)));
    expect(
      trippingLook(Look.highSun).extension<TrippingLook>()!.trackWidth,
      greaterThan(
        trippingLook(Look.light).extension<TrippingLook>()!.trackWidth,
      ),
    );
  });
}
