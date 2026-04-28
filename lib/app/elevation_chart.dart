import 'dart:math';

import 'package:flutter/material.dart';

import '../history/elevation_profile.dart';

/// Height along a journey: one line per recorded segment, never joined.
class ElevationChart extends StatelessWidget {
  const ElevationChart({super.key, required this.profile});

  final ElevationProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label:
          'Height from ${profile.lowest.round()} to '
          '${profile.highest.round()} metres',
      excludeSemantics: true,
      child: SizedBox(
        height: 96,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${profile.highest.round()} m', style: small),
                Text('${profile.lowest.round()} m', style: small),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CustomPaint(
                painter: _ProfilePainter(profile, color: scheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter(this.profile, {required this.color});

  final ElevationProfile profile;
  final Color color;

  /// The least height range drawn, so GPS noise on flat ground is not
  /// stretched into hills.
  static const _minRange = 50.0;

  @override
  void paint(Canvas canvas, Size size) {
    final range = max(_minRange, profile.highest - profile.lowest);
    final floor = (profile.highest + profile.lowest - range) / 2;
    final width = profile.meters > 0 ? profile.meters : 1;
    Offset at((double, double) point) => Offset(
      point.$1 / width * size.width,
      size.height - (point.$2 - floor) / range * size.height,
    );
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color.withValues(alpha: 0.12);
    for (final line in profile.lines) {
      if (line.length < 2) continue;
      final path = Path();
      for (final (i, point) in line.indexed) {
        final o = at(point);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      final area = Path.from(path)
        ..lineTo(at(line.last).dx, size.height)
        ..lineTo(at(line.first).dx, size.height)
        ..close();
      canvas
        ..drawPath(area, fill)
        ..drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_ProfilePainter old) =>
      !identical(old.profile, profile) || old.color != color;
}
