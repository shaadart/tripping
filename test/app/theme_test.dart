import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/app/tokens.dart';

void main() {
  group('tokens', () {
    test('spacing steps rise on a 4 dp grid', () {
      const steps = [
        Space.xs,
        Space.sm,
        Space.md,
        Space.lg,
        Space.xl,
        Space.xxl,
      ];
      for (var i = 0; i < steps.length; i++) {
        expect(steps[i] % 4, 0, reason: '${steps[i]}');
        if (i > 0) expect(steps[i], greaterThan(steps[i - 1]));
      }
    });

    test('three corner radii and touch targets of at least 48 dp', () {
      expect(Corner.small, lessThan(Corner.medium));
      expect(Corner.medium, lessThan(Corner.large));
      expect(Touch.min, greaterThanOrEqualTo(48));
      expect(Touch.secondary, greaterThan(Touch.min));
      expect(Touch.primary, greaterThan(Touch.secondary));
    });
  });

  for (final look in Look.values) {
    group('${look.name} look', () {
      final theme = trippingLook(look);
      final scheme = theme.colorScheme;

      test('every neutral role is warm, never seed-tinted', () {
        final neutrals = {
          'surface': scheme.surface,
          'surfaceContainer': scheme.surfaceContainer,
          'surfaceContainerHigh': scheme.surfaceContainerHigh,
          'surfaceContainerHighest': scheme.surfaceContainerHighest,
          'onSurface': scheme.onSurface,
          'onSurfaceVariant': scheme.onSurfaceVariant,
          'outline': scheme.outline,
          'outlineVariant': scheme.outlineVariant,
          'inverseSurface': scheme.inverseSurface,
        };
        for (final MapEntry(key: name, value: c) in neutrals.entries) {
          expect(c.r, greaterThanOrEqualTo(c.b), reason: '$name is cool');
        }
      });

      test('surfaces step one way from canvas to raised, with no tint', () {
        final tiers = [
          for (final c in [
            scheme.surface,
            scheme.surfaceContainer,
            scheme.surfaceContainerHigh,
            scheme.surfaceContainerHighest,
          ])
            c.computeLuminance(),
        ];
        // Lighter toward the reader, except high sun: white cannot go
        // lighter, so raised ground is a pale grey instead.
        final sign = look == Look.highSun ? -1 : 1;
        for (var i = 1; i < tiers.length; i++) {
          expect(sign * (tiers[i] - tiers[i - 1]), greaterThan(0));
        }
        expect(scheme.surfaceTint, Colors.transparent);
      });

      test('components are flat, rounded by tokens and touch-sized', () {
        final filled = theme.filledButtonTheme.style!;
        final outlined = theme.outlinedButtonTheme.style!;
        final text = theme.textButtonTheme.style!;
        final icon = theme.iconButtonTheme.style!;
        expect(filled.minimumSize!.resolve({})!.height, Touch.primary);
        expect(outlined.minimumSize!.resolve({})!.height, Touch.secondary);
        expect(text.minimumSize!.resolve({})!.height, Touch.min);
        expect(icon.minimumSize!.resolve({})!.width, Touch.min);
        expect(filled.elevation!.resolve({}), 0);

        expect(theme.cardTheme.elevation, 0);
        expect(theme.dialogTheme.elevation, 0);
        expect(theme.bottomSheetTheme.elevation, 0);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.cardTheme.surfaceTintColor, Colors.transparent);

        RoundedRectangleBorder? shape(ShapeBorder? s) =>
            s is RoundedRectangleBorder ? s : null;
        expect(shape(theme.cardTheme.shape)!.borderRadius, Corner.mediumRadius);
        expect(
          shape(theme.dialogTheme.shape)!.borderRadius,
          Corner.largeRadius,
        );
        expect(
          shape(theme.bottomSheetTheme.shape)!.borderRadius,
          Corner.sheetRadius,
        );
      });

      test('fields sit on raised ground with a visible boundary', () {
        final input = theme.inputDecorationTheme;
        expect(input.filled, isTrue);
        expect(input.fillColor, scheme.surfaceContainerHighest);
        final border = input.enabledBorder! as OutlineInputBorder;
        expect(border.borderSide.color, scheme.outline);
        expect(border.borderRadius, Corner.mediumRadius);
        final focus = input.focusedBorder! as OutlineInputBorder;
        expect(focus.borderSide.color, scheme.primary);
        expect(focus.borderSide.width, greaterThanOrEqualTo(2));
      });

      test('the type scale is ordered and numbers keep fixed width', () {
        final t = theme.textTheme;
        final sizes = [
          t.displayLarge!.fontSize!,
          t.displayMedium!.fontSize!,
          t.headlineMedium!.fontSize!,
          t.titleLarge!.fontSize!,
          t.bodyLarge!.fontSize!,
          t.bodyMedium!.fontSize!,
          t.bodySmall!.fontSize!,
        ];
        for (var i = 1; i < sizes.length; i++) {
          expect(sizes[i], lessThanOrEqualTo(sizes[i - 1]));
        }
        expect(t.bodyMedium!.fontSize, greaterThanOrEqualTo(14));
        expect(t.displayLarge!.fontFeatures, isNotEmpty);
      });
    });
  }

  test('high sun draws heavier type and stronger boundaries', () {
    final light = trippingLook(Look.light);
    final sun = trippingLook(Look.highSun);
    expect(
      sun.textTheme.bodyMedium!.fontWeight!.value,
      greaterThan(light.textTheme.bodyMedium!.fontWeight!.value),
    );
    final a = light.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    final b = sun.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    expect(b.borderSide.width, greaterThan(a.borderSide.width));
  });

  testWidgets('every control stays at least 48 dp at 200% text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingLook(Look.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Start')),
                OutlinedButton(onPressed: () {}, child: const Text('Pause')),
                TextButton(onPressed: () {}, child: const Text('Skip')),
                IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
                const TextField(),
              ],
            ),
          ),
        ),
      ),
    );
    for (final type in [
      FilledButton,
      OutlinedButton,
      TextButton,
      IconButton,
      TextField,
    ]) {
      expect(
        tester.getSize(find.byType(type)).height,
        greaterThanOrEqualTo(Touch.min),
        reason: '$type',
      );
    }
  });
}
