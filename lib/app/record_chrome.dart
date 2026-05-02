library;

import 'package:flutter/material.dart';
import '../journey/journey.dart';
import '../recording/recorder.dart';
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
    final (label, icon, color, description) = switch (state) {
      Idle() => (
        'Tripping',
        Icons.explore_outlined,
        scheme.onSurface,
        'Tripping',
      ),
      Recording(:final journey) => (
        'Recording',
        journey.mode == JourneyMode.road
            ? Icons.directions_car_rounded
            : Icons.terrain_rounded,
        scheme.primary,
        'Recording · ${modeName(journey.mode)}',
      ),
      Paused(:final journey) => (
        'Paused',
        Icons.pause_rounded,
        scheme.onSurfaceVariant,
        'Paused · ${modeName(journey.mode)}',
      ),
      Interrupted(:final journey) => (
        'Stopped',
        Icons.warning_amber_rounded,
        warningColor(context),
        'Stopped · ${modeName(journey.mode)}',
      ),
    };
    return Semantics(
      label: description,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
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
  Widget build(BuildContext context) => Text(
    'Where to?',
    style: Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
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
                    child: CustomPaint(
                      painter: _ModeArtPainter(art, scheme.primary),
                    ),
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

/// A route along a road, or contour rings around a summit, drawn faintly in
/// the corner of the card the way the map will draw them.
class _ModeArtPainter extends CustomPainter {
  const _ModeArtPainter(this.art, this.ink);
  final ModeArt art;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint stroke(double alpha, double width) => Paint()
      ..color = ink.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    switch (art) {
      case ModeArt.road:
        final route = Path()
          ..moveTo(w * .5, h * .5)
          ..cubicTo(w * .62, h * .4, w * .6, h * .3, w * .76, h * .22)
          ..cubicTo(w * .86, h * .16, w * .94, h * .12, w * 1.02, h * .08);
        canvas.drawPath(route, stroke(.16, 9));
        canvas.drawPath(route, stroke(.5, 3));
      case ModeArt.expedition:
        final centre = Offset(w * .78, h * .3);
        for (var i = 1; i <= 4; i++) {
          canvas.drawOval(
            Rect.fromCenter(
              center: centre,
              width: w * .12 * i,
              height: h * .1 * i,
            ),
            stroke(.5 - i * .08, 2),
          );
        }
        canvas.drawCircle(
          centre,
          3,
          Paint()..color = ink.withValues(alpha: .6),
        );
    }
  }

  @override
  bool shouldRepaint(_ModeArtPainter old) => old.art != art || old.ink != ink;
}
