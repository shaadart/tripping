import 'package:flutter/material.dart';

import 'map_symbols.dart';

/// Optional explanation: the map itself stays quiet.
class MapKeyButton extends StatelessWidget {
  const MapKeyButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    style: IconButton.styleFrom(
      minimumSize: const Size(48, 48),
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
    tooltip: 'Map symbols',
    icon: const Icon(Icons.layers_outlined),
    onPressed: () => showMapKey(context),
  );
}

Future<void> showMapKey(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Theme.of(context).colorScheme.surface,
  showDragHandle: true,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .85,
  ),
  builder: (_) => const _MapKey(),
);

class _MapKey extends StatelessWidget {
  const _MapKey();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: LayoutBuilder(
        builder: (context, box) {
          final columns = MediaQuery.textScalerOf(context).scale(14) > 22
              ? 1
              : 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (index, tile) in <Widget>[
                const _KeyRow(
                  sample: _LineSample(route: true),
                  title: 'Planned way',
                  detail: 'Arrows point towards the destination.',
                ),
                const _KeyRow(
                  sample: _LineSample(),
                  title: 'Your track',
                  detail: 'Gaps are places we did not record.',
                ),
                const _KeyRow(
                  sample: _LineSample(straight: true),
                  title: 'Direction only',
                  detail: 'A straight line, not a road or path.',
                ),
                const _KeyRow(
                  sample: MapSymbolGlyph(MapSymbol.origin),
                  title: 'Start',
                ),
                const _KeyRow(
                  sample: MapSymbolGlyph(MapSymbol.destination),
                  title: 'Destination',
                  detail: 'Where you intend to go.',
                ),
                const _KeyRow(
                  sample: MapSymbolGlyph(MapSymbol.finish),
                  title: 'Finish',
                  detail: 'Where recording ended, even if you did not arrive.',
                ),
                const _KeyRow(
                  sample: MapSymbolGlyph(MapSymbol.marked),
                  title: 'Marked here',
                  detail: 'A point saved from your position.',
                ),
                const _KeyRow(
                  sample: MapSymbolGlyph(MapSymbol.planned),
                  title: 'Planned point',
                  detail: 'A place chosen on the map.',
                ),
                const _KeyRow(
                  sample: _AccuracySample(),
                  title: 'GPS uncertainty',
                  detail:
                      'The shaded area is the reported accuracy, not a boundary. A neutral marker is last known or approximate.',
                ),
              ].indexed)
                SizedBox(
                  width: index == 8
                      ? box.maxWidth
                      : (box.maxWidth - 12 * (columns - 1)) / columns,
                  child: tile,
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.sample, required this.title, this.detail});
  final Widget sample;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Semantics(
    label: detail == null ? title : '$title. $detail',
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(height: 48, child: Center(child: sample)),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LineSample extends StatelessWidget {
  const _LineSample({this.route = false, this.straight = false});
  final bool route;
  final bool straight;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 40,
    child: CustomPaint(
      painter: _LinePainter(MapVisuals(context), route, straight),
    ),
  );
}

class _AccuracySample extends StatelessWidget {
  const _AccuracySample();

  @override
  Widget build(BuildContext context) {
    final color = MapVisuals(context).recorded;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .10),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Icon(Icons.circle, size: 10, color: color),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.visuals, this.route, this.straight);
  final MapVisuals visuals;
  final bool route;
  final bool straight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = route || straight ? visuals.route : visuals.recorded
      ..strokeWidth = straight
          ? 3
          : route
          ? visuals.routeWidth
          : visuals.trackWidth
      ..strokeCap = StrokeCap.round;
    if (straight) {
      for (double x = 3; x < size.width - 4; x += 10) {
        canvas.drawLine(Offset(x, 20), Offset(x + 3, 20), paint);
      }
    } else {
      canvas.drawLine(const Offset(3, 20), Offset(size.width - 3, 20), paint);
      if (route) {
        canvas.drawPath(
          Path()
            ..moveTo(22, 16)
            ..lineTo(27, 20)
            ..lineTo(22, 24),
          Paint()
            ..color = visuals.arrow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      visuals.scheme != old.visuals.scheme ||
      route != old.route ||
      straight != old.straight;
}
