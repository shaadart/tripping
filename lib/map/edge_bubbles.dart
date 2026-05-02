import 'dart:math';

import 'package:flutter/material.dart';

import '../app/components.dart';
import '../app/identity_marker.dart';
import '../app/tokens.dart';
import '../group/group_sync.dart';
import '../group/sharing.dart';
import '../journey/journey.dart';
import 'edge_geometry.dart';

/// A companion who is off the map, at the edge nearest to them: their own
/// marker (or how many, for several in one direction), a pointer their way
/// and how far. Tapping brings them into view.
class EdgeBubbleView extends StatelessWidget {
  const EdgeBubbleView({
    super.key,
    required this.bubble,
    required this.companions,
    required this.now,
    required this.here,
    required this.onShow,
  });

  final EdgeBubble bubble;

  /// The companions in [bubble], in its order.
  final List<Companion> companions;
  final DateTime now;

  /// This phone's position, for the distance; null without one.
  final Fix? here;
  final VoidCallback onShow;

  static const size = Touch.min;

  bool _faded(Companion c) {
    final at = c.positionAt;
    if (c.shared.phase != JourneyPhase.recording || at == null) return true;
    final age = now.difference(at);
    return freshnessOf(age.isNegative ? Duration.zero : age, c.shared.mode) ==
        Freshness.stale;
  }

  String _away(Companion c) {
    final here = this.here, fix = c.shared.fix;
    if (here == null || fix == null) return '';
    return distanceAndDirection(here, fix);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final single = companions.length == 1 ? companions.single : null;
    final label = single != null
        ? '${single.name}, ${_away(single)}, off the map. Show them'
        : '${companions.length} companions ${_away(companions.first)}, off '
              'the map: ${companions.map((c) => c.name).join(', ')}. Show them';
    // At large text the map is short and labels would cover neighbours:
    // the distance stays in the spoken label and the companion panel.
    final roomy = MediaQuery.textScalerOf(context).scale(11) <= 16;
    final distance = single == null || !roomy ? null : _away(single);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onShow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onShow,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // The pointer, outside the disc, towards them.
              Transform.rotate(
                angle: bubble.angle,
                child: CustomPaint(
                  size: const Size.square(size),
                  painter: _Pointer(scheme.onSurface),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: raisedGround(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                alignment: Alignment.center,
                child: single != null
                    ? IdentityMarker(
                        identity: single.shared.identity,
                        hollow: _faded(single),
                        size: 28,
                      )
                    : Text(
                        '${companions.length}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
              ),
              if (distance != null && distance.isNotEmpty)
                Positioned(
                  // On the side away from the edge, so it is never cut off.
                  top: cos(bubble.angle) < -0.5 ? null : size - 2,
                  bottom: cos(bubble.angle) < -0.5 ? size - 2 : null,
                  left: sin(bubble.angle) < -0.5 ? 0 : null,
                  right: sin(bubble.angle) > 0.5 ? 0 : null,
                  child: MapChrome(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.xs + 2,
                      vertical: 1,
                    ),
                    child: Text(
                      distance,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small filled triangle at the rim of the bubble, pointing up (the
/// widget around it turns it).
class _Pointer extends CustomPainter {
  const _Pointer(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final tip = c.dy - min(size.width, size.height) / 2 - 4;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, tip)
        ..lineTo(c.dx - 7, tip + 9)
        ..lineTo(c.dx + 7, tip + 9)
        ..close(),
      Paint()..color = ink,
    );
  }

  @override
  bool shouldRepaint(_Pointer old) => old.ink != ink;
}
