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
  });
  final MapIdentity identity;
  final double size;
  final bool hollow;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '${identity.description}${hollow ? ', last known' : ''}',
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkerPainter(identity, hollow)),
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
  const _MarkerPainter(this.identity, this.hollow);
  final MapIdentity identity;
  final bool hollow;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44, size.height / 44);
    final path = Path();
    switch (identity.shape) {
      case MarkerShape.rosette:
        for (var i = 0; i < 16; i++) {
          final angle = -math.pi / 2 + i * math.pi / 8;
          final radius = i.isEven ? 17.0 : 13.5;
          final x = 22 + math.cos(angle) * radius;
          final y = 22 + math.sin(angle) * radius;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      case MarkerShape.reed:
        path.moveTo(6, 29);
        path.cubicTo(5, 13, 20, 5, 37, 6);
        path.cubicTo(39, 23, 29, 39, 6, 36);
        path.close();
      case MarkerShape.gate:
        path.moveTo(7, 37);
        path.lineTo(7, 16);
        path.lineTo(13, 16);
        path.lineTo(13, 8);
        path.lineTo(31, 8);
        path.lineTo(31, 16);
        path.lineTo(37, 16);
        path.lineTo(37, 37);
        path.close();
      case MarkerShape.tablet:
        path.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8, 5, 28, 34),
            const Radius.circular(13),
          ),
        );
    }
    // A dark outer keyline + white casing survives bright, dark and busy maps.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF26221E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
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
          ..strokeWidth = 1.3,
      );
    }
    final text = TextPainter(
      text: TextSpan(
        text: identity.initials,
        style: TextStyle(
          color: hollow ? const Color(0xFF45413A) : Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
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
      hollow != old.hollow;
}
