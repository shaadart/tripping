import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../group/identity.dart';

/// Native plugins assign screen density to decoded image bytes. The PNG is
/// rendered at 3x; compensate for the device density to keep it 44 logical px.
double identityMapIconScale(BuildContext context) =>
    MediaQuery.devicePixelRatioOf(context) / 3;

/// The SAME painter supplies the welcome preview, lists and native map icon.
class IdentityMarker extends StatelessWidget {
  const IdentityMarker({
    super.key,
    required this.identity,
    this.size = 44,
    this.hollow = false,
    this.showInitials = true,
  });
  final MapIdentity identity;
  final double size;
  final bool hollow;
  final bool showInitials;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '${identity.description}${hollow ? ', last known' : ''}',
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkerPainter(identity, hollow, showInitials),
      ),
    ),
  );
}

Future<Uint8List> identityMarkerPng(
  MapIdentity identity, {
  bool hollow = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(3);
  _MarkerPainter(identity, hollow).paint(canvas, const Size(44, 44));
  final picture = recorder.endRecording();
  final image = await picture.toImage(132, 132);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.identity, this.hollow, [this.showInitials = true]);
  final MapIdentity identity;
  final bool hollow;
  final bool showInitials;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44, size.height / 44);
    var path = Path();
    switch (identity.shape) {
      case MarkerShape.rosette:
        path = _softPolygon([
          for (var i = 0; i < 16; i++)
            Offset(
              22 +
                  math.cos(-math.pi / 2 + i * math.pi / 8) *
                      (i.isEven ? 18 : 15),
              22 +
                  math.sin(-math.pi / 2 + i * math.pi / 8) *
                      (i.isEven ? 18 : 15),
            ),
        ]);
      case MarkerShape.reed:
        path.moveTo(7, 31);
        path.cubicTo(7, 16, 19, 7, 33, 6);
        path.quadraticBezierTo(37, 6, 37, 10);
        path.cubicTo(36, 26, 25, 37, 10, 37);
        path.quadraticBezierTo(6, 37, 7, 31);
        path.close();
      case MarkerShape.gate:
        path = _softPolygon(const [
          Offset(6, 37),
          Offset(6, 17),
          Offset(12, 17),
          Offset(12, 7),
          Offset(32, 7),
          Offset(32, 17),
          Offset(38, 17),
          Offset(38, 37),
        ]);
      case MarkerShape.tablet:
        path.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8, 5, 28, 34),
            const Radius.circular(11),
          ),
        );
    }
    // Solid pigment, no white casing. Neutral outline belongs only to the
    // existing last-known treatment, never to a live identity.
    canvas.drawPath(
      path,
      Paint()
        ..color = hollow
            ? const Color(0xFFF6F1E7)
            : Color(identity.colour.argb),
    );
    if (hollow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF625D55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }
    if (!showInitials) {
      canvas.restore();
      return;
    }
    final text = TextPainter(
      text: TextSpan(
        text: identity.initials,
        style: TextStyle(
          color: hollow ? const Color(0xFF45413A) : Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (text.width > 22) {
      canvas.save();
      canvas.translate(22, 22);
      canvas.scale(22 / text.width);
      text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
      canvas.restore();
    } else {
      text.paint(canvas, Offset((44 - text.width) / 2, (44 - text.height) / 2));
    }
    text.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      identity.name != old.identity.name ||
      identity.colour != old.identity.colour ||
      identity.shape != old.identity.shape ||
      hollow != old.hollow ||
      showInitials != old.showInitials;
}

Path _softPolygon(List<Offset> points) {
  final path = Path();
  for (var i = 0; i < points.length; i++) {
    final vertex = points[i];
    final before = Offset.lerp(
      vertex,
      points[(i - 1 + points.length) % points.length],
      .28,
    )!;
    final after = Offset.lerp(vertex, points[(i + 1) % points.length], .28)!;
    if (i == 0) {
      path.moveTo(before.dx, before.dy);
    } else {
      path.lineTo(before.dx, before.dy);
    }
    path.quadraticBezierTo(vertex.dx, vertex.dy, after.dx, after.dy);
  }
  return path..close();
}
