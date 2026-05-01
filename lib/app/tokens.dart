import 'package:flutter/widgets.dart';

/// Spacing steps, in dp. Every gap and padding in the app is one of these.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Side margin of a screen.
  static const gutter = lg;
}

/// Corner radii, in dp. Three steps: small for fields and chips, medium for
/// buttons, cards and panels, large for sheets and dialogs.
abstract final class Corner {
  static const small = 12.0;
  static const medium = 16.0;
  static const large = 24.0;

  static const smallRadius = BorderRadius.all(Radius.circular(small));
  static const mediumRadius = BorderRadius.all(Radius.circular(medium));
  static const largeRadius = BorderRadius.all(Radius.circular(large));
  static const sheetRadius = BorderRadius.vertical(top: Radius.circular(large));
}

/// Touch target heights, in dp. Nothing tappable is smaller than [min]; the
/// one main action of a screen is [primary].
abstract final class Touch {
  static const min = 48.0;
  static const secondary = 56.0;
  static const primary = 64.0;
}

/// Durations of the few transitions the app has. Motion explains a change; it
/// is never ambient.
abstract final class Motion {
  static const quick = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 200);

  /// [d], or no time at all when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}
