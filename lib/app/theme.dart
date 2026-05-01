import 'package:flutter/material.dart';

import 'tokens.dart';

/// The palette from DESIGN.md: warm paper by day, warm night by night, ember
/// for recording, and a high-sun variant for bright daylight. Every text
/// colour meets WCAG 4.5:1 on its background and every control boundary 3:1
/// (test/app/contrast_test.dart). No role is left to a seed colour: each
/// neutral is a warm tone chosen here.
abstract final class Palette {
  static const paper = Color(0xFFF6F1E7);
  static const paperRaised = Color(0xFFFFFDF8);
  static const ink = Color(0xFF1F1B16);
  static const inkMuted = Color(0xFF5C554B);
  static const ember = Color(0xFFC2410C);
  static const river = Color(0xFF0F6E8C);
  static const moss = Color(0xFF3F6B3A);
  static const signal = Color(0xFFA34F08);
  static const brick = Color(0xFFA12D1F);

  /// Faint line between neighbours (decoration) and the stronger boundary of
  /// a control (3:1 against paper).
  static const hairline = Color(0xFFD9CFBD);
  static const outline = Color(0xFF8A8378);

  /// Soft fills for selected or informational surfaces, with their text.
  static const emberTint = Color(0xFFFBE6DA);
  static const onEmberTint = Color(0xFF5A1F06);
  static const riverTint = Color(0xFFDCEDF3);
  static const onRiverTint = Color(0xFF0A3A4A);
  static const mossTint = Color(0xFFE3EDDD);
  static const onMossTint = Color(0xFF22391F);

  static const night = Color(0xFF14120F);
  static const nightRaised = Color(0xFF1E1B17);
  static const nightInk = Color(0xFFF3EDE2);
  static const nightInkMuted = Color(0xFFB9B0A3);
  static const emberNight = Color(0xFFF26B3A);
  static const riverNight = Color(0xFF4FB3D9);
  static const mossNight = Color(0xFF7FB174);
  static const signalNight = Color(0xFFF59E0B);
  static const brickNight = Color(0xFFF2917F);
  static const nightHairline = Color(0xFF36312A);
  static const nightOutline = Color(0xFF8A8378);
  static const emberDeep = Color(0xFF4A2112);
  static const onEmberDeep = Color(0xFFFBD9C8);
  static const riverDeep = Color(0xFF123F4E);
  static const onRiverDeep = Color(0xFFCDEAF5);
  static const mossDeep = Color(0xFF24391F);
  static const onMossDeep = Color(0xFFD2E6CB);

  /// High sun: white, near-black ink and a deeper ember, for reading in
  /// direct sunlight.
  static const sun = Color(0xFFFFFFFF);
  static const sunRaised = Color(0xFFF2EFEA);
  static const sunInk = Color(0xFF0F0D0B);
  static const sunInkMuted = Color(0xFF3A342D);
  static const sunEmber = Color(0xFF9A3412);
  static const sunSignal = Color(0xFF8A3A00);
  static const sunBrick = Color(0xFF8A1F12);
  static const sunHairline = Color(0xFF8A8378);
  static const sunOutline = Color(0xFF5C554B);
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

/// Every colour a look decides. Surfaces step toward the reader from
/// [surface] (the canvas) to [raised] (fields, cards, sheets): lighter by day
/// and by night, a pale grey in high sun where the canvas is already white.
class _Tones {
  const _Tones({
    required this.brightness,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.tertiary,
    required this.onTertiary,
    required this.error,
    required this.onError,
    required this.primaryTint,
    required this.onPrimaryTint,
    required this.secondaryTint,
    required this.onSecondaryTint,
    required this.tertiaryTint,
    required this.onTertiaryTint,
    required this.inverse,
    required this.onInverse,
    required this.inversePrimary,
  });

  final Brightness brightness;
  final Color surface, raised, ink, muted, hairline, outline;
  final Color primary, onPrimary, secondary, onSecondary;
  final Color tertiary, onTertiary, error, onError;
  final Color primaryTint, onPrimaryTint, secondaryTint, onSecondaryTint;
  final Color tertiaryTint, onTertiaryTint;
  final Color inverse, onInverse, inversePrimary;

  ColorScheme get scheme {
    Color step(double t) => Color.lerp(surface, raised, t)!;
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryTint,
      onPrimaryContainer: onPrimaryTint,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryTint,
      onSecondaryContainer: onSecondaryTint,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryTint,
      onTertiaryContainer: onTertiaryTint,
      error: error,
      onError: onError,
      errorContainer: Color.lerp(surface, error, .12)!,
      onErrorContainer: error,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceDim: surface,
      surfaceBright: raised,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: step(.5),
      surfaceContainerHigh: step(.8),
      surfaceContainerHighest: raised,
      outline: outline,
      outlineVariant: hairline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: inverse,
      onInverseSurface: onInverse,
      inversePrimary: inversePrimary,
      surfaceTint: Colors.transparent,
    );
  }
}

const _light = _Tones(
  brightness: Brightness.light,
  surface: Palette.paper,
  raised: Palette.paperRaised,
  ink: Palette.ink,
  muted: Palette.inkMuted,
  hairline: Palette.hairline,
  outline: Palette.outline,
  primary: Palette.ember,
  onPrimary: Colors.white,
  secondary: Palette.river,
  onSecondary: Colors.white,
  tertiary: Palette.moss,
  onTertiary: Colors.white,
  error: Palette.brick,
  onError: Colors.white,
  primaryTint: Palette.emberTint,
  onPrimaryTint: Palette.onEmberTint,
  secondaryTint: Palette.riverTint,
  onSecondaryTint: Palette.onRiverTint,
  tertiaryTint: Palette.mossTint,
  onTertiaryTint: Palette.onMossTint,
  inverse: Palette.ink,
  onInverse: Palette.paper,
  inversePrimary: Palette.emberNight,
);

const _dark = _Tones(
  brightness: Brightness.dark,
  surface: Palette.night,
  raised: Palette.nightRaised,
  ink: Palette.nightInk,
  muted: Palette.nightInkMuted,
  hairline: Palette.nightHairline,
  outline: Palette.nightOutline,
  primary: Palette.emberNight,
  onPrimary: Palette.night,
  secondary: Palette.riverNight,
  onSecondary: Palette.night,
  tertiary: Palette.mossNight,
  onTertiary: Palette.night,
  error: Palette.brickNight,
  onError: Palette.night,
  primaryTint: Palette.emberDeep,
  onPrimaryTint: Palette.onEmberDeep,
  secondaryTint: Palette.riverDeep,
  onSecondaryTint: Palette.onRiverDeep,
  tertiaryTint: Palette.mossDeep,
  onTertiaryTint: Palette.onMossDeep,
  inverse: Palette.nightInk,
  onInverse: Palette.night,
  inversePrimary: Palette.ember,
);

const _sun = _Tones(
  brightness: Brightness.light,
  surface: Palette.sun,
  raised: Palette.sunRaised,
  ink: Palette.sunInk,
  muted: Palette.sunInkMuted,
  hairline: Palette.sunHairline,
  outline: Palette.sunOutline,
  primary: Palette.sunEmber,
  onPrimary: Colors.white,
  secondary: Palette.river,
  onSecondary: Colors.white,
  tertiary: Palette.moss,
  onTertiary: Colors.white,
  error: Palette.sunBrick,
  onError: Colors.white,
  primaryTint: Palette.emberTint,
  onPrimaryTint: Palette.onEmberTint,
  secondaryTint: Palette.riverTint,
  onSecondaryTint: Palette.onRiverTint,
  tertiaryTint: Palette.mossTint,
  onTertiaryTint: Palette.onMossTint,
  inverse: Palette.sunInk,
  onInverse: Palette.sun,
  inversePrimary: Palette.emberNight,
);

/// One type scale for the whole app. Vital numbers use the display roles and
/// tabular figures so digits do not jitter as they change. Heavier in high
/// sun: thin strokes wash out in glare.
TextTheme _typeScale({required bool highSun}) {
  final regular = highSun ? FontWeight.w500 : FontWeight.w400;
  final strong = highSun ? FontWeight.w700 : FontWeight.w600;
  const tabular = [FontFeature.tabularFigures()];
  return TextTheme(
    displayLarge: TextStyle(
      fontSize: 34,
      height: 1.1,
      fontWeight: strong,
      fontFeatures: tabular,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      height: 1.15,
      fontWeight: strong,
      fontFeatures: tabular,
    ),
    displaySmall: TextStyle(
      fontSize: 24,
      height: 1.2,
      fontWeight: strong,
      fontFeatures: tabular,
    ),
    headlineLarge: TextStyle(fontSize: 28, height: 1.2, fontWeight: strong),
    headlineMedium: TextStyle(fontSize: 24, height: 1.25, fontWeight: strong),
    headlineSmall: TextStyle(fontSize: 20, height: 1.3, fontWeight: strong),
    titleLarge: TextStyle(fontSize: 20, height: 1.3, fontWeight: strong),
    titleMedium: TextStyle(fontSize: 16, height: 1.35, fontWeight: strong),
    titleSmall: TextStyle(fontSize: 14, height: 1.35, fontWeight: strong),
    bodyLarge: TextStyle(fontSize: 16, height: 1.4, fontWeight: regular),
    bodyMedium: TextStyle(fontSize: 14, height: 1.4, fontWeight: regular),
    bodySmall: TextStyle(fontSize: 12, height: 1.4, fontWeight: regular),
    labelLarge: TextStyle(fontSize: 16, height: 1.25, fontWeight: strong),
    labelMedium: TextStyle(fontSize: 12, height: 1.3, fontWeight: strong),
    labelSmall: TextStyle(fontSize: 11, height: 1.3, fontWeight: strong),
  );
}

ThemeData trippingLook(Look look) {
  final tones = switch (look) {
    Look.light => _light,
    Look.dark => _dark,
    Look.highSun => _sun,
  };
  final highSun = look == Look.highSun;
  final scheme = tones.scheme;
  // Component styles are built from the theme's merged text theme, which
  // carries the platform font family; the raw scale has none.
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: _typeScale(
      highSun: highSun,
    ).apply(bodyColor: tones.ink, displayColor: tones.ink),
  );
  final text = base.textTheme;
  final warning = switch (look) {
    Look.light => Palette.signal,
    Look.dark => Palette.signalNight,
    Look.highSun => Palette.sunSignal,
  };

  const mediumShape = RoundedRectangleBorder(borderRadius: Corner.mediumRadius);
  final boundary = BorderSide(color: tones.outline, width: highSun ? 2 : 1);
  final hairline = BorderSide(color: tones.hairline);
  OutlineInputBorder field(Color colour, double width) => OutlineInputBorder(
    borderRadius: Corner.mediumRadius,
    borderSide: BorderSide(color: colour, width: width),
  );

  return base.copyWith(
    scaffoldBackgroundColor: tones.surface,
    canvasColor: tones.surface,
    iconTheme: IconThemeData(color: tones.ink, size: 24),
    splashFactory: InkRipple.splashFactory,
    dividerTheme: DividerThemeData(
      color: tones.hairline,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tones.surface,
      foregroundColor: tones.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(Touch.primary),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        shape: mediumShape,
        elevation: 0,
        textStyle: text.labelLarge?.copyWith(fontSize: 18),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(Touch.secondary),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        shape: mediumShape,
        foregroundColor: tones.ink,
        side: boundary,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(Touch.min, Touch.min),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        shape: const RoundedRectangleBorder(borderRadius: Corner.smallRadius),
        foregroundColor: tones.primary,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(Touch.min, Touch.min),
        iconSize: 24,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: tones.raised,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: Corner.mediumRadius,
        side: hairline,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tones.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Corner.largeRadius,
        side: hairline,
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium?.copyWith(color: tones.muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tones.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: Corner.sheetRadius),
      clipBehavior: Clip.antiAlias,
      dragHandleColor: tones.outline,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      minTileHeight: Touch.secondary,
      iconColor: tones.muted,
      textColor: tones.ink,
      titleTextStyle: text.titleMedium?.copyWith(color: tones.ink),
      subtitleTextStyle: text.bodyMedium?.copyWith(color: tones.muted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tones.raised,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.lg,
      ),
      border: field(tones.outline, highSun ? 2 : 1),
      enabledBorder: field(tones.outline, highSun ? 2 : 1),
      focusedBorder: field(tones.primary, 2),
      errorBorder: field(tones.error, 1.5),
      focusedErrorBorder: field(tones.error, 2),
      labelStyle: text.bodyLarge?.copyWith(color: tones.muted),
      hintStyle: text.bodyLarge?.copyWith(color: tones.muted),
      helperStyle: text.bodySmall?.copyWith(color: tones.muted),
      errorStyle: text.bodySmall?.copyWith(color: tones.error),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tones.inverse,
      contentTextStyle: text.bodyMedium?.copyWith(color: tones.onInverse),
      actionTextColor: tones.inversePrimary,
      elevation: 0,
      shape: mediumShape,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tones.inverse,
        borderRadius: Corner.smallRadius,
      ),
      textStyle: text.bodySmall?.copyWith(color: tones.onInverse),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tones.primary,
      linearTrackColor: tones.hairline,
      circularTrackColor: tones.hairline,
    ),
    extensions: [
      TrippingLook(
        look: look,
        mapStyle: mapAsset(look),
        trackWidth: highSun ? 7 : 5,
        warning: warning,
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
