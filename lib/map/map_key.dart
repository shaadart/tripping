import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';

import '../app/components.dart';
import '../app/identity_marker.dart';
import '../app/map_ground.dart';
import '../app/tokens.dart';
import '../group/identity.dart';
import 'map_symbols.dart';

/// Optional explanation: the map itself stays quiet.
class MapKeyButton extends StatelessWidget {
  const MapKeyButton({super.key, this.identity});

  /// Drawn as you in the guide, so it matches the marker on the map.
  final MapIdentity? identity;

  @override
  Widget build(BuildContext context) => MapChrome(
    child: IconButton(
      tooltip: 'Map symbols',
      icon: const Icon(Icons.layers_outlined),
      onPressed: () => showMapKey(context, identity: identity),
    ),
  );
}

Future<void> showMapKey(BuildContext context, {MapIdentity? identity}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (_) => _MapKey(identity: identity ?? const MapIdentity()),
    );

/// What the map can draw. The guide shows each one in place; tapping one says
/// what it means.
enum _Part {
  planned('Planned way', 'Arrows point towards the destination.'),
  track('Your track', 'Gaps are places we did not record.'),
  direction('Direction only', 'A straight line, not a road or path.'),
  start('Start', 'Where recording began.'),
  destination('Destination', 'Where you intend to go.'),
  finish('Finish', 'Where recording ended, even if you did not arrive.'),
  marked('Marked here', 'A point saved from your position.'),
  plannedPoint('Planned point', 'A place chosen on the map.'),
  accuracy(
    'GPS uncertainty',
    'The shaded area is the reported accuracy, not a boundary. '
        'A neutral marker is last known or approximate.',
  );

  const _Part(this.title, this.detail);
  final String title;
  final String detail;
}

class _MapKey extends StatefulWidget {
  const _MapKey({required this.identity});
  final MapIdentity identity;

  @override
  State<_MapKey> createState() => _MapKeyState();
}

class _MapKeyState extends State<_MapKey> {
  _Part _part = _Part.planned;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Scene(
            selected: _part,
            identity: widget.identity,
            onSelect: (part) => setState(() => _part = part),
          ),
          const SizedBox(height: Space.md),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.quick),
            child: _PartCard(key: ValueKey(_part), part: _part),
          ),
        ],
      ),
    ),
  );
}

/// The selected part: its drawing, its name and what it means.
class _PartCard extends StatelessWidget {
  const _PartCard({super.key, required this.part});
  final _Part part;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      label: '${part.title}. ${part.detail}',
      excludeSemantics: true,
      child: MapChrome(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          children: [
            SizedBox(width: 56, child: Center(child: _sample(part))),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    part.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    part.detail,
                    style: text.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _sample(_Part part) => switch (part) {
  _Part.planned => const _LineSample(route: true),
  _Part.track => const _LineSample(),
  _Part.direction => const _LineSample(straight: true),
  _Part.start => const MapSymbolGlyph(MapSymbol.origin),
  _Part.destination => const MapSymbolGlyph(MapSymbol.destination),
  _Part.finish => const MapSymbolGlyph(MapSymbol.finish),
  _Part.marked => const MapSymbolGlyph(MapSymbol.marked),
  _Part.plannedPoint => const MapSymbolGlyph(MapSymbol.planned),
  _Part.accuracy => const _AccuracySample(),
};

/// Where everything sits, as fractions of the scene, so the drawing and the
/// tap targets always agree. A road runs from the start, past a saved point,
/// breaks for a while, reaches you, and carries on as the planned way.
class _Layout {
  _Layout(this.size) {
    final w = size.width, h = size.height;
    Offset at(double x, double y) => Offset(w * x, h * y);
    you = at(.46, .48);
    destination = at(.80, .22);
    start = at(.11, .90);
    finish = at(.85, .86);
    plannedPoint = at(.73, .62);
    track = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(w * .08, h * .70, w * .30, h * .72, you.dx, you.dy);
    planned = Path()
      ..moveTo(you.dx, you.dy)
      ..cubicTo(
        w * .58,
        h * .44,
        w * .62,
        h * .24,
        destination.dx,
        destination.dy,
      );
    ended = Path()
      ..moveTo(w * .54, h * .92)
      ..cubicTo(w * .66, h * .80, w * .76, h * .92, finish.dx, finish.dy);
    directionFrom = at(.09, .17);
    directionTo = at(.36, .10);
    final trackMetric = track.computeMetrics().single;
    marked = _point(trackMetric, .34);
    trackMid = _point(trackMetric, .66);
    plannedMid = _point(planned.computeMetrics().single, .5);
    directionMid = Offset.lerp(directionFrom, directionTo, .5)!;
  }

  final Size size;
  late final Offset you, destination, start, finish, plannedPoint;
  late final Offset marked, trackMid, plannedMid, directionMid;
  late final Offset directionFrom, directionTo;
  late final Path track, planned, ended;

  static Offset _point(PathMetric metric, double t) =>
      metric.getTangentForOffset(metric.length * t)!.position;

  Offset anchor(_Part part) => switch (part) {
    _Part.planned => plannedMid,
    _Part.track => trackMid,
    _Part.direction => directionMid,
    _Part.start => start,
    _Part.destination => destination,
    _Part.finish => finish,
    _Part.marked => marked,
    _Part.plannedPoint => plannedPoint,
    _Part.accuracy => you,
  };
}

class _Scene extends StatelessWidget {
  const _Scene({
    required this.selected,
    required this.identity,
    required this.onSelect,
  });

  final _Part selected;
  final MapIdentity identity;
  final ValueChanged<_Part> onSelect;

  @override
  Widget build(BuildContext context) {
    final ground = MapGround.of(groundLook(context));
    final visuals = MapVisuals(context);
    final scheme = Theme.of(context).colorScheme;
    // Names beside the symbols while they fit; the card carries them always.
    final names = MediaQuery.textScalerOf(context).scale(12) <= 15;
    return ClipRRect(
      borderRadius: Corner.largeRadius,
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, box) {
            final layout = _Layout(box.biggest);
            Widget spot(_Part part, Widget child) {
              final at = layout.anchor(part);
              return Positioned(
                left: at.dx - Touch.min / 2,
                top: at.dy - Touch.min / 2,
                width: Touch.min,
                height: Touch.min,
                child: Semantics(
                  button: true,
                  selected: part == selected,
                  label: '${part.title}. ${part.detail}',
                  excludeSemantics: true,
                  onTap: () => onSelect(part),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(part),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (part == selected)
                          Pop(
                            trigger: part,
                            child: Container(
                              width: Touch.min,
                              height: Touch.min,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        child,
                      ],
                    ),
                  ),
                ),
              );
            }

            Widget name(_Part part, double dy) {
              final at = layout.anchor(part);
              return Positioned(
                left: at.dx,
                top: at.dy + dy,
                child: FractionalTranslation(
                  translation: const Offset(-.5, 0),
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ground.land.withValues(alpha: .88),
                        borderRadius: Corner.smallRadius,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: Space.xs / 2,
                        ),
                        child: Text(
                          part.title,
                          maxLines: 1,
                          softWrap: false,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(painter: MapGroundPainter(ground)),
                  ),
                ),
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: _RoadPainter(layout, visuals, ground),
                    ),
                  ),
                ),
                Positioned(
                  left: layout.you.dx - 32,
                  top: layout.you.dy - 32,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: visuals.recorded.withValues(alpha: .12),
                          border: Border.all(
                            color: visuals.recorded.withValues(alpha: .45),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                spot(
                  _Part.accuracy,
                  IdentityMarker(identity: identity, size: 32),
                ),
                spot(_Part.planned, const SizedBox.shrink()),
                spot(_Part.track, const SizedBox.shrink()),
                spot(_Part.direction, const SizedBox.shrink()),
                spot(_Part.start, const MapSymbolGlyph(MapSymbol.origin)),
                spot(_Part.marked, const MapSymbolGlyph(MapSymbol.marked)),
                spot(_Part.finish, const MapSymbolGlyph(MapSymbol.finish)),
                spot(
                  _Part.plannedPoint,
                  const MapSymbolGlyph(MapSymbol.planned),
                ),
                spot(
                  _Part.destination,
                  const MapSymbolGlyph(MapSymbol.destination),
                ),
                if (names) ...[
                  name(_Part.planned, -34),
                  name(_Part.track, 16),
                  name(_Part.direction, 14),
                  name(_Part.start, 22),
                  name(_Part.marked, 20),
                  name(_Part.finish, 22),
                  name(_Part.plannedPoint, 20),
                  name(_Part.destination, 28),
                  name(_Part.accuracy, 34),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The scene's lines, drawn as the map draws them: the planned way as a wide
/// corridor with arrows, the recorded track narrow and solid with a gap, and
/// a straight dashed line where only a direction is known.
class _RoadPainter extends CustomPainter {
  const _RoadPainter(this.layout, this.visuals, this.ground);
  final _Layout layout;
  final MapVisuals visuals;
  final MapGround ground;

  @override
  void paint(Canvas canvas, Size size) {
    Paint line(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Planned way: corridor, then arrows along it.
    canvas.drawPath(layout.planned, line(visuals.route, visuals.routeWidth));
    final metric = layout.planned.computeMetrics().single;
    final arrow = line(visuals.arrow, 2);
    for (final t in [.28, .72]) {
      final Tangent? at = metric.getTangentForOffset(metric.length * t);
      if (at == null) continue;
      canvas.save();
      canvas.translate(at.position.dx, at.position.dy);
      canvas.rotate(-at.angle);
      canvas.drawPath(
        Path()
          ..moveTo(-3, -4)
          ..lineTo(2, 0)
          ..lineTo(-3, 4),
        arrow,
      );
      canvas.restore();
    }
    // Recorded track, with the part that was not recorded left out.
    final trackMetric = layout.track.computeMetrics().single;
    for (final (from, to) in [(0.0, .6), (.74, 1.0)]) {
      final part = trackMetric.extractPath(
        trackMetric.length * from,
        trackMetric.length * to,
      );
      canvas.drawPath(part, line(ground.land, visuals.trackCasingWidth + 2));
      canvas.drawPath(part, line(visuals.recorded, visuals.trackWidth));
    }
    final ended = layout.ended;
    canvas.drawPath(ended, line(ground.land, visuals.trackCasingWidth + 2));
    canvas.drawPath(ended, line(visuals.recorded, visuals.trackWidth));
    // Direction only: dashes, not a way.
    final dash = line(visuals.route, 3);
    final from = layout.directionFrom, to = layout.directionTo;
    final length = (to - from).distance;
    final step = (to - from) / length;
    for (var d = 0.0; d < length - 3; d += 10) {
      canvas.drawLine(from + step * d, from + step * (d + 3), dash);
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) =>
      old.layout.size != layout.size ||
      old.visuals.scheme != visuals.scheme ||
      old.ground != ground;
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
