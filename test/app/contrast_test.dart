import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/map_ground.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/group/identity.dart';

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
          'error on surface': (scheme.error, scheme.surface),
          'error on raised': (scheme.error, scheme.surfaceContainerHighest),
          'error label': (scheme.onError, scheme.error),
          'ink on raised': (scheme.onSurface, scheme.surfaceContainerHighest),
          'muted on raised': (
            scheme.onSurfaceVariant,
            scheme.surfaceContainerHighest,
          ),
          'ink on selected tint': (
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          ),
          'river on selected tint': (
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          ),
          'moss on selected tint': (
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer,
          ),
          'snackbar text': (scheme.onInverseSurface, scheme.inverseSurface),
        };
        for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
        }
      });

      test('design-system pairings added in DS-3..6 read at 4.5:1', () {
        final raised = scheme.surfaceContainerHighest;
        final ground = MapGround.of(look);
        Color over(Color tint, double alpha, Color base) =>
            Color.alphaBlend(tint.withValues(alpha: alpha), base);
        final pairs = {
          'ember totals on surface': (scheme.primary, scheme.surface),
          'warning detail on raised': (extras.warning, raised),
          'reached badge': (
            scheme.onSurface,
            over(scheme.primary, .12, raised),
          ),
          'not reached badge': (
            scheme.onSurface,
            over(scheme.onSurfaceVariant, .12, raised),
          ),
          'guide name on ground': (
            scheme.onSurface,
            over(ground.land, .88, ground.park),
          ),
          'note text on warning tint': (
            scheme.onSurface,
            over(extras.warning, .1, raised),
          ),
          'note text on error tint': (
            scheme.onSurface,
            over(scheme.error, .1, raised),
          ),
        };
        for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
        }
      });

      test('a control boundary reads at 3:1 against surface and raised', () {
        for (final ground in [scheme.surface, scheme.surfaceContainerHighest]) {
          expect(
            contrast(scheme.outline, ground),
            greaterThanOrEqualTo(3),
            reason: 'outline on $ground',
          );
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

  test('white reads on every identity colour (identity action, initials)', () {
    for (final colour in IdentityColour.values) {
      expect(
        contrast(Colors.white, Color(colour.argb)),
        greaterThanOrEqualTo(4.5),
        reason: colour.label,
      );
    }
  });
}
