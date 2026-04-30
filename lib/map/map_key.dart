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
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (_) => const _MapKey(),
    ),
  );
}

class _MapKey extends StatelessWidget {
  const _MapKey();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('On your map', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const _KeyRow(
            sample: _LineSample(route: true),
            title: 'Planned way',
            detail: 'Arrows point towards the destination.',
          ),
          const _KeyRow(
            sample: _LineSample(),
            title: 'Recorded ground',
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
            title: 'Recorded finish',
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
            sample: Icon(Icons.gps_not_fixed, size: 30),
            title: 'GPS uncertainty',
            detail:
                'The shaded area is the reported accuracy, not a boundary. A neutral marker is last known or approximate.',
          ),
        ],
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        ExcludeSemantics(
          child: SizedBox(width: 56, child: Center(child: sample)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (detail != null)
                Text(
                  detail!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
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
