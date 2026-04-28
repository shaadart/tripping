import 'package:flutter/material.dart';

/// The palette from DESIGN.md: warm paper by day, warm night by night, ember
/// for recording, and a high-sun variant for bright daylight. Every text
/// colour meets WCAG 4.5:1 on its background (test/app/contrast_test.dart).
abstract final class Palette {
  static const paper = Color(0xFFF6F1E7);
  static const paperRaised = Color(0xFFFFFDF8);
  static const ink = Color(0xFF1F1B16);
  static const inkMuted = Color(0xFF5C554B);
  static const ember = Color(0xFFC2410C);
  static const river = Color(0xFF0F6E8C);
  static const moss = Color(0xFF3F6B3A);
  static const signal = Color(0xFFA34F08);

  static const night = Color(0xFF14120F);
  static const nightRaised = Color(0xFF1E1B17);
  static const nightInk = Color(0xFFF3EDE2);
  static const nightInkMuted = Color(0xFFB9B0A3);
  static const emberNight = Color(0xFFF26B3A);
  static const riverNight = Color(0xFF4FB3D9);
  static const mossNight = Color(0xFF7FB174);
  static const signalNight = Color(0xFFF59E0B);

  /// High sun: white, near-black ink and a deeper ember, for reading in
  /// direct sunlight.
  static const sun = Color(0xFFFFFFFF);
  static const sunRaised = Color(0xFFF2EFEA);
  static const sunInk = Color(0xFF0F0D0B);
  static const sunInkMuted = Color(0xFF3A342D);
  static const sunEmber = Color(0xFF9A3412);
  static const sunSignal = Color(0xFF8A3A00);
}

/// The three looks Tripping has.
enum Look { light, dark, highSun }

/// What differs per look beyond the colour scheme.
@immutable
class TrippingLook extends ThemeExtension<TrippingLook> {
  const TrippingLook({
    required this.look,
    required this.mapStyle,
    required this.trackWidth,
    required this.warning,
  });

  final Look look;

  /// The bundled basemap style asset.
  final String mapStyle;

  /// Width of a recorded track, in pixels.
  final double trackWidth;

  /// Amber for things that need attention but are not failures.
  final Color warning;

  @override
  TrippingLook copyWith() => this;

  @override
  TrippingLook lerp(TrippingLook? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

ThemeData trippingTheme(Brightness brightness) =>
    trippingLook(brightness == Brightness.dark ? Look.dark : Look.light);

ThemeData trippingLook(Look look) {
  final dark = look == Look.dark;
  final (surface, raised, ink, muted, primary, onPrimary) = switch (look) {
    Look.light => (
      Palette.paper,
      Palette.paperRaised,
      Palette.ink,
      Palette.inkMuted,
      Palette.ember,
      Colors.white,
    ),
    Look.dark => (
      Palette.night,
      Palette.nightRaised,
      Palette.nightInk,
      Palette.nightInkMuted,
      Palette.emberNight,
      Palette.night,
    ),
    Look.highSun => (
      Palette.sun,
      Palette.sunRaised,
      Palette.sunInk,
      Palette.sunInkMuted,
      Palette.sunEmber,
      Colors.white,
    ),
  };
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.ember,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: primary,
        onPrimary: onPrimary,
        secondary: dark ? Palette.riverNight : Palette.river,
        tertiary: dark ? Palette.mossNight : Palette.moss,
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerHighest: raised,
      );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(20)),
  );
  // Heavier type in high sun: thin strokes wash out in glare.
  final weight = look == Look.highSun ? FontWeight.w700 : FontWeight.w600;
  final label = TextStyle(fontSize: 18, fontWeight: weight);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        shape: shape,
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        shape: shape,
        textStyle: label,
        side: BorderSide(color: primary, width: look == Look.highSun ? 2 : 1),
      ),
    ),
    extensions: [
      TrippingLook(
        look: look,
        mapStyle: mapAsset(look),
        trackWidth: look == Look.highSun ? 7 : 5,
        warning: switch (look) {
          Look.light => Palette.signal,
          Look.dark => Palette.signalNight,
          Look.highSun => Palette.sunSignal,
        },
      ),
    ],
  );
}

/// The bundled basemap style of [look].
String mapAsset(Look look) => switch (look) {
  Look.light => 'assets/map/light.json',
  Look.dark => 'assets/map/dark.json',
  Look.highSun => 'assets/map/sun.json',
};

/// The look of the current theme.
TrippingLook lookOf(BuildContext context) =>
    Theme.of(context).extension<TrippingLook>()!;

/// Amber for things that need attention but are not failures.
Color warningColor(BuildContext context) => lookOf(context).warning;
