import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Tripping's brand mark: upper-left Expedition mountain ridge in moss,
/// lower-right Road highway in river with rhythmic lane pills, and a
/// dancing ember S-curve trail with a navigator arrow puck surfing the crest
/// on warm sandstone paper.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 24, this.look});

  final double size;

  /// When null, uses the current theme's [Look].
  final Look? look;

  @override
  Widget build(BuildContext context) {
    final activeLook =
        look ?? Theme.of(context).extension<TrippingLook>()?.look ?? Look.light;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: BrandMarkPainter(look: activeLook)),
    );
  }
}

/// Renders the [BrandMarkPainter] to a square PNG of [dimension] pixels.
Future<Uint8List> brandMarkPng({
  int dimension = 512,
  Look look = Look.light,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  BrandMarkPainter(look: look).paint(canvas, Size.square(dimension.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(dimension, dimension);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({this.look = Look.light, this.clipped = true});

  final Look look;

  /// Whether to clip to a rounded squircle. False when drawing an unclipped
  /// adaptive-icon layer.
  final bool clipped;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 256, size.height / 256);

    final (paper, moss, ember, river, border) = switch (look) {
      Look.light => (
        Palette.paper,
        Palette.moss,
        Palette.ember,
        Palette.river,
        Palette.hairline,
      ),
      Look.dark => (
        Palette.paper,
        Palette.moss,
        Palette.emberNight,
        Palette.river,
        Palette.nightHairline,
      ),
      Look.highSun => (
        Palette.sun,
        Palette.moss,
        Palette.sunEmber,
        Palette.river,
        Palette.sunOutline,
      ),
    };

    const rect = Rect.fromLTWH(0, 0, 256, 256);
    final squircle = RRect.fromRectAndRadius(rect, const Radius.circular(58));
    if (clipped) {
      canvas.clipRRect(squircle);
    }

    // 1. Warm Sandstone background (high-luminance figure-ground separator).
    canvas.drawRect(rect, Paint()..color = paper);

    // 2. Upper-left Expedition mountain ridge (soft rounded twin peaks, bounded
    // along the S-curve spine so only warm sandstone separates trail and road).
    final mountain = Path()
      ..moveTo(-16, 224)
      ..lineTo(-16, 162)
      ..lineTo(54, 48)
      ..quadraticBezierTo(72, 18, 94, 46)
      ..lineTo(118, 76)
      ..lineTo(140, 50)
      ..quadraticBezierTo(156, 30, 174, 54)
      ..lineTo(206, 98)
      ..lineTo(104, 156)
      ..close();
    canvas.drawPath(mountain, Paint()..color = moss);

    // 3. Lower-right Road Journey curving highway corridor.
    final road = Path()
      ..moveTo(54, 272)
      ..cubicTo(106, 212, 168, 152, 272, 108)
      ..lineTo(272, 272)
      ..close();
    canvas.drawPath(road, Paint()..color = river);

    // Rhythmic highway lane dashes (staccato pill beats).
    final dashPaint = Paint()
      ..color = paper
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(136, 238), const Offset(164, 210), dashPaint);
    canvas.drawLine(const Offset(192, 184), const Offset(224, 158), dashPaint);

    // 4. The Musical S-Curve Trail (Sandstone separation moat + Ember ribbon).
    final sCurve = Path()
      ..moveTo(-8, 232)
      ..cubicTo(36, 252, 82, 198, 104, 156)
      ..cubicTo(132, 104, 194, 86, 266, 82);

    canvas.drawPath(
      sCurve,
      Paint()
        ..color = paper
        ..style = PaintingStyle.stroke
        ..strokeWidth = 68
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      sCurve,
      Paint()
        ..color = ember
        ..style = PaintingStyle.stroke
        ..strokeWidth = 40
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // 5. The Surfing Navigator Arrow Puck (#10 hero focal point at golden ratio).
    canvas.save();
    canvas.translate(148, 122);
    canvas.rotate(-math.pi / 5.2);
    final arrow = _roundedArrow();
    canvas.drawPath(
      arrow,
      Paint()
        ..color = paper
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(arrow, Paint()..color = ember);
    canvas.restore();

    if (clipped) {
      canvas.drawRRect(
        squircle.deflate(2),
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
    canvas.restore();
  }

  static Path _roundedArrow() {
    // Soft-cornered navigator delta pointing right (+X) before rotation.
    const pts = [
      Offset(30, 0),
      Offset(-22, -24),
      Offset(-12, 0),
      Offset(-22, 24),
    ];
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final v = pts[i];
      final prev = pts[(i - 1 + pts.length) % pts.length];
      final next = pts[(i + 1) % pts.length];
      final b = Offset.lerp(v, prev, 0.24)!;
      final a = Offset.lerp(v, next, 0.24)!;
      if (i == 0) {
        path.moveTo(b.dx, b.dy);
      } else {
        path.lineTo(b.dx, b.dy);
      }
      path.quadraticBezierTo(v.dx, v.dy, a.dx, a.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(BrandMarkPainter old) =>
      old.look != look || old.clipped != clipped;
}
