import 'package:flutter/material.dart';

import 'theme.dart';

/// The map's own ground colours, so the preview shows the marker where it
/// will live. Values follow tool/map_styles.dart.
class MapGround {
  const MapGround({
    required this.land,
    required this.park,
    required this.water,
    required this.road,
    required this.casing,
    required this.minor,
  });
  final Color land, park, water, road, casing, minor;

  static MapGround of(Look look) => look == Look.dark ? dark : light;

  static const light = MapGround(
    land: Color(0xFFF8F8F3),
    park: Color(0xFFE8EFDE),
    water: Color(0xFFD1E6EC),
    road: Color(0xFFFFFFFF),
    casing: Color(0xFFE2DFD3),
    minor: Color(0xFFECEAE0),
  );
  static const dark = MapGround(
    land: Color(0xFF141E20),
    park: Color(0xFF1D3026),
    water: Color(0xFF183743),
    road: Color(0xFF2C3C3F),
    casing: Color(0xFF0E1618),
    minor: Color(0xFF1F2C2F),
  );
}

Look groundLook(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<TrippingLook>()?.look ??
      (theme.brightness == Brightness.dark ? Look.dark : Look.light);
}

/// A few blocks of park, a river and crossing streets, drawn to the card.
class MapGroundPainter extends CustomPainter {
  const MapGroundPainter(this.ground);
  final MapGround ground;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint fill(Color c) => Paint()..color = c;
    Paint line(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawRect(Offset.zero & size, fill(ground.land));
    for (final r in [
      Rect.fromLTRB(w * .04, h * .08, w * .36, h * .44),
      Rect.fromLTRB(w * .66, h * .6, w * 1.04, h * 1.06),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(28)),
        fill(ground.park),
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(-w * .05, h * .8)
        ..cubicTo(w * .3, h * 1.0, w * .5, h * .58, w * 1.05, h * .74),
      line(ground.water, 26),
    );
    for (final y in [.2, .62]) {
      canvas.drawLine(
        Offset(0, h * y),
        Offset(w, h * (y + .06)),
        line(ground.minor, 4),
      );
    }
    final main = Path()
      ..moveTo(-w * .05, h * .34)
      ..cubicTo(w * .35, h * .2, w * .6, h * .5, w * 1.05, h * .34);
    final cross = Path()
      ..moveTo(w * .54, -h * .05)
      ..quadraticBezierTo(w * .44, h * .5, w * .6, h * 1.05);
    for (final path in [main, cross]) {
      canvas.drawPath(path, line(ground.casing, 15));
    }
    for (final path in [main, cross]) {
      canvas.drawPath(path, line(ground.road, 11));
    }
  }

  @override
  bool shouldRepaint(MapGroundPainter old) => old.ground != ground;
}
