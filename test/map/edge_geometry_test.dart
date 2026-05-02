import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/map/edge_geometry.dart';

void main() {
  // A 400 x 700 map under a 100 px toolbar band.
  const screen = Rect.fromLTWH(0, 0, 400, 700);
  final usable = Rect.fromLTRB(0, 100, 400, 700);
  final centre = usable.center;

  List<EdgeBubble> place(List<EdgeTarget> targets, {List<Rect>? occluders}) =>
      placeEdgeBubbles(
        usable: usable,
        targets: targets,
        occluders: occluders ?? const [],
      );

  EdgeTarget away(String id, double angle, [double distance = 5000]) =>
      EdgeTarget(
        id,
        centre + Offset(sin(angle) * distance, -cos(angle) * distance),
      );

  test('someone in view gets no bubble', () {
    expect(place([EdgeTarget('a', centre)]), isEmpty);
    expect(screen.contains(centre), isTrue);
  });

  test('one bubble on each edge, pointing at them', () {
    for (final (angle, onEdge) in [
      (0.0, (EdgeBubble b) => b.centre.dy < usable.top + 40),
      (pi / 2, (EdgeBubble b) => b.centre.dx > usable.right - 40),
      (pi, (EdgeBubble b) => b.centre.dy > usable.bottom - 40),
      (-pi / 2, (EdgeBubble b) => b.centre.dx < usable.left + 40),
    ]) {
      final bubble = place([away('a', angle)]).single;
      expect(onEdge(bubble), isTrue, reason: 'angle $angle');
      expect(usable.contains(bubble.centre), isTrue);
      final error = ((bubble.angle - angle + pi) % (2 * pi)) - pi;
      expect(error.abs(), lessThan(0.05), reason: 'angle $angle');
    }
  });

  test('towards a corner, the bubble sits by that corner', () {
    final bubble = place([away('a', pi / 4, 1e6)]).single;
    expect(bubble.centre.dx, greaterThan(usable.right - 60));
    expect(bubble.centre.dy, lessThan(usable.top + 300));
  });

  test('a bubble never sits on a control; it slides off it', () {
    // The follow and overview buttons, bottom right.
    final tools = Rect.fromLTWH(336, 580, 48, 104);
    final bubble = place(
      [EdgeTarget('a', const Offset(420, 640))],
      occluders: [tools],
    ).single;
    expect(tools.inflate(24).contains(bubble.centre), isFalse);
    expect(bubble.centre.dx, greaterThan(usable.right - 40));
  });

  test('someone under the toolbar or a button counts as out of view', () {
    final mark = Rect.fromLTWH(16, 620, 120, 48);
    expect(
      place([EdgeTarget('a', const Offset(60, 640))], occluders: [mark]),
      hasLength(1),
    );
    // Under the toolbar band (above the usable area).
    expect(place([EdgeTarget('b', const Offset(200, 50))]), hasLength(1));
  });

  test('companions in about the same direction share one bubble', () {
    final bubbles = place([
      away('a', 0.05),
      away('b', 0.08),
      away('c', pi / 2),
    ]);
    expect(bubbles, hasLength(2));
    expect(bubbles.map((b) => (b.ids.toList()..sort()).join()), contains('ab'));
  });

  test('neighbours across the start of the border loop are one group', () {
    // The border loop starts at the top-left corner of the bubble track
    // (the usable area less a bubble and its margin): either side of it.
    final track = usable.deflate(28);
    final corner = track.topLeft - centre;
    final angle = atan2(corner.dx, -corner.dy);
    final bubbles = place([away('a', angle - 0.02), away('b', angle + 0.02)]);
    expect(bubbles, hasLength(1));
    expect(bubbles.single.ids.toSet(), {'a', 'b'});
  });

  test('the order companions arrive in changes nothing', () {
    final targets = [
      away('a', 0.3),
      away('b', 1.9),
      away('c', 2.0),
      away('d', -2.5),
    ];
    String describe(List<EdgeBubble> bubbles) => [
      for (final b in bubbles)
        '${b.ids.toSet().toList()..sort()}@'
            '${b.centre.dx.round()},${b.centre.dy.round()}',
    ].join(' ');
    expect(
      describe(place(targets.reversed.toList())),
      describe(place(targets)),
    );
  });

  test('a position the camera cannot project still points their way', () {
    final bubble = place([
      const EdgeTarget('a', Offset(double.nan, double.nan), direction: pi),
    ]).single;
    expect(bubble.centre.dy, greaterThan(usable.bottom - 40));
    expect(bubble.angle, closeTo(pi, 0.01));
  });

  test('no room at all: no bubbles, no error', () {
    expect(
      placeEdgeBubbles(
        usable: const Rect.fromLTWH(0, 0, 30, 30),
        targets: [EdgeTarget('a', const Offset(500, 500))],
      ),
      isEmpty,
    );
  });

  test('a tilted camera\'s mirrored projection is recognised', () {
    const centre = Offset(200, 400);
    // Projected far above the centre, but the companion is due south.
    expect(looksMirrored(const Offset(200, -300), centre, pi), isTrue);
    // Projected below and to the right, and they are south-east: believed.
    expect(looksMirrored(const Offset(600, 900), centre, 3 * pi / 4), isFalse);
    // At the centre there is nothing to compare.
    expect(looksMirrored(centre, centre, 0), isFalse);
  });
}
