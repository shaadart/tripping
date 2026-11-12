library;

import 'package:flutter/material.dart';
import '../journey/journey.dart';
import '../recording/recorder.dart';
import 'brand_mark.dart';
import 'components.dart';
import 'format.dart';
import 'theme.dart';
import 'tokens.dart';

class Header extends StatelessWidget {
  const Header({super.key, required this.state});

  final RecorderState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, leading, description) = switch (state) {
      Idle() => ('Tripping', const BrandMark(size: 22), 'Tripping'),
      Recording(:final journey) => (
        'Recording',
        Icon(
          journey.mode == JourneyMode.road
              ? Icons.directions_car_rounded
              : Icons.terrain_rounded,
          size: 20,
          color: scheme.primary,
        ),
        'Recording · ${modeName(journey.mode)}',
      ),
      Paused(:final journey) => (
        'Paused',
        Icon(Icons.pause_rounded, size: 20, color: scheme.onSurfaceVariant),
        'Paused · ${modeName(journey.mode)}',
      ),
      Interrupted(:final journey) => (
        'Stopped',
        Icon(
          Icons.warning_amber_rounded,
          size: 20,
          color: warningColor(context),
        ),
        'Stopped · ${modeName(journey.mode)}',
      ),
    };
    return Semantics(
      label: description,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two actions side by side, leaving more of the screen to the map; one
/// above the other when large text would not fit.
class ActionPair extends StatelessWidget {
  const ActionPair(this.first, this.second, {super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(18) > 22) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 12), second],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

/// Switches the high-contrast look for direct sunlight; filled while on.
class HighSunButton extends StatelessWidget {
  const HighSunButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final on = lookOf(context).look == Look.highSun;
    return MapChrome(
      child: IconButton(
        onPressed: onPressed,
        isSelected: on,
        icon: const Icon(Icons.wb_sunny_outlined),
        selectedIcon: const Icon(Icons.wb_sunny),
        tooltip: on ? 'High-sun mode on' : 'High-sun mode',
      ),
    );
  }
}

/// The idle panel's one question. The two answers below it show themselves.
class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const ExcludeSemantics(child: BrandMark(size: 28)),
      const SizedBox(width: Space.sm),
      Expanded(
        child: Text(
          'Where to?',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

/// How a journey will be drawn: a way along roads, or ground read by contour.
enum ModeArt { road, expedition }

/// One answer to "Where to?": a drawn sample of what that journey looks like
/// on the map, its name, and a tap that starts it.
class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.label,
    required this.icon,
    required this.art,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final ModeArt art;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: raisedGround(context),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: Corner.mediumRadius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onPressed,
          excludeFromSemantics: true,
          child: SizedBox(
            height: 112,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(painter: _ModeArtPainter(art, scheme)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(icon, color: scheme.primary, size: 28),
                      const SizedBox(height: Space.xs),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two halves of Tripping's brand mark drawn gently in the corner of each
/// mode card: the river road corridor + ember S-trail for [ModeArt.road], or
/// the moss mountain ridge + ember summit trail for [ModeArt.expedition].
class _ModeArtPainter extends CustomPainter {
  const _ModeArtPainter(this.art, this.scheme);
  final ModeArt art;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint stroke(Color c, double alpha, double width) => Paint()
      ..color = c.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (art) {
      case ModeArt.road:
        final corridor = Path()
          ..moveTo(w * .48, h * .58)
          ..cubicTo(w * .64, h * .52, w * .72, h * .24, w * 1.04, h * .14);
        canvas.drawPath(corridor, stroke(scheme.secondary, .22, 16));
        canvas.drawLine(
          Offset(w * .62, h * .48),
          Offset(w * .70, h * .38),
          stroke(scheme.surfaceContainerHighest, .75, 2.5),
        );
        canvas.drawLine(
          Offset(w * .80, h * .28),
          Offset(w * .90, h * .20),
          stroke(scheme.surfaceContainerHighest, .75, 2.5),
        );
        final track = Path()
          ..moveTo(w * .44, h * .46)
          ..cubicTo(w * .60, h * .48, w * .66, h * .18, w * .98, h * .08);
        canvas.drawPath(track, stroke(scheme.primary, .55, 4));
      case ModeArt.expedition:
        final ridge = Path()
          ..moveTo(w * .44, h * .58)
          ..lineTo(w * .62, h * .20)
          ..quadraticBezierTo(w * .67, h * .10, w * .73, h * .22)
          ..lineTo(w * .80, h * .34)
          ..lineTo(w * .87, h * .20)
          ..quadraticBezierTo(w * .92, h * .12, w * .97, h * .24)
          ..lineTo(w * 1.06, h * .58)
          ..close();
        canvas.drawPath(
          ridge,
          Paint()..color = scheme.tertiary.withValues(alpha: .18),
        );
        final trail = Path()
          ..moveTo(w * .52, h * .58)
          ..cubicTo(w * .62, h * .52, w * .68, h * .28, w * .92, h * .16);
        canvas.drawPath(trail, stroke(scheme.primary, .55, 4));
    }
  }

  @override
  bool shouldRepaint(_ModeArtPainter old) =>
      old.art != art || old.scheme != scheme;
}
