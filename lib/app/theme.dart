import 'package:flutter/material.dart';

/// The candidate palette from DESIGN.md: warm paper by day, warm night by
/// night, ember for recording. D1 validates it outdoors.
abstract final class Palette {
  static const paper = Color(0xFFF6F1E7);
  static const paperRaised = Color(0xFFFFFDF8);
  static const ink = Color(0xFF1F1B16);
  static const inkMuted = Color(0xFF5C554B);
  static const ember = Color(0xFFC2410C);
  static const river = Color(0xFF0F6E8C);
  static const moss = Color(0xFF3F6B3A);
  static const signal = Color(0xFFB45309);

  static const night = Color(0xFF14120F);
  static const nightRaised = Color(0xFF1E1B17);
  static const nightInk = Color(0xFFF3EDE2);
  static const nightInkMuted = Color(0xFFB9B0A3);
  static const emberNight = Color(0xFFF26B3A);
  static const riverNight = Color(0xFF4FB3D9);
  static const mossNight = Color(0xFF7FB174);
  static const signalNight = Color(0xFFF59E0B);
}

ThemeData trippingTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.ember,
        brightness: brightness,
      ).copyWith(
        primary: dark ? Palette.emberNight : Palette.ember,
        onPrimary: dark ? Palette.night : Colors.white,
        secondary: dark ? Palette.riverNight : Palette.river,
        tertiary: dark ? Palette.mossNight : Palette.moss,
        surface: dark ? Palette.night : Palette.paper,
        onSurface: dark ? Palette.nightInk : Palette.ink,
        onSurfaceVariant: dark ? Palette.nightInkMuted : Palette.inkMuted,
        surfaceContainerHighest: dark
            ? Palette.nightRaised
            : Palette.paperRaised,
      );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(20)),
  );
  const label = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
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
        minimumSize: const Size.fromHeight(56),
        shape: shape,
        textStyle: label,
      ),
    ),
  );
}

/// Amber for things that need attention but are not failures.
Color warningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Palette.signalNight
    : Palette.signal;
