import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/theme.dart';

/// Presentation only. One drawing supplies native sprites and the map key.
enum MapSymbol {
  origin,
  finish,
  destination,
  marked,
  planned,
  routeArrow;

  String get image => 'tripping-$name';
  Size get size => switch (this) {
    MapSymbol.destination => const Size(40, 48),
    MapSymbol.routeArrow => const Size(16, 16),
    _ => const Size(40, 40),
  };
}

class MapVisuals {
  MapVisuals(BuildContext context)
    : // Native sprites outlive theme animation: use the settled look tokens.
      scheme = trippingLook(lookOf(context).look).colorScheme,
      look = lookOf(context);

  final ColorScheme scheme;
  final TrippingLook look;
  Color get route => scheme.secondary;
  Color get recorded => scheme.primary;
  Color get ground => scheme.surface;
  Color get marked => scheme.tertiary;
  Color get arrow => look.look == Look.dark ? Palette.night : Colors.white;
  double get routeWidth => look.look == Look.highSun ? 12 : 10;
  double get trackWidth => look.trackWidth;
  double get trackCasingWidth => trackWidth + 1.5;
}

class MapSymbolGlyph extends StatelessWidget {
  const MapSymbolGlyph(this.symbol, {super.key});
  final MapSymbol symbol;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: symbol.size,
    child: CustomPaint(painter: _SymbolPainter(symbol, MapVisuals(context))),
  );
}

Future<void> registerMapSymbols(
  MapLibreMapController map,
  BuildContext context,
) async {
  final visuals = MapVisuals(context);
  for (final symbol in MapSymbol.values) {
    await map.addImage(symbol.image, await mapSymbolPng(symbol, visuals));
  }
}

Future<Uint8List> mapSymbolPng(MapSymbol symbol, MapVisuals visuals) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(3);
  _SymbolPainter(symbol, visuals).paint(canvas, symbol.size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (symbol.size.width * 3).round(),
    (symbol.size.height * 3).round(),
  );
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _SymbolPainter extends CustomPainter {
  const _SymbolPainter(this.symbol, this.visuals);
  final MapSymbol symbol;
  final MapVisuals visuals;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = visuals.recorded;
    switch (symbol) {
      case MapSymbol.origin:
        // An open ring can remain visible around a finish on a closed loop.
        canvas.drawCircle(
          const Offset(20, 20),
          14,
          Paint()..color = visuals.ground,
        );
        canvas.drawCircle(
          const Offset(20, 20),
          11,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      case MapSymbol.finish:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(12, 12, 16, 16),
            const Radius.circular(4),
          ),
          paint,
        );
      case MapSymbol.destination:
        final pin = Path()
          ..moveTo(20, 47)
          ..cubicTo(16, 38, 4, 31, 4, 19)
          ..cubicTo(4, -2, 36, -2, 36, 19)
          ..cubicTo(36, 31, 24, 38, 20, 47)
          ..close();
        canvas.drawPath(pin, paint..color = visuals.route);
        // A flag inside the pin remains legible with no downloaded fonts.
        final flag = Path()
          ..moveTo(16, 27)
          ..lineTo(16, 12)
          ..lineTo(26, 12)
          ..lineTo(24, 16)
          ..lineTo(26, 20)
          ..lineTo(16, 20);
        canvas.drawPath(
          flag,
          Paint()
            ..color = visuals.arrow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round,
        );
      case MapSymbol.marked:
      case MapSymbol.planned:
        final diamond = Path()
          ..moveTo(20, 6)
          ..quadraticBezierTo(21, 6, 22, 8)
          ..lineTo(32, 18)
          ..quadraticBezierTo(34, 20, 32, 22)
          ..lineTo(22, 32)
          ..quadraticBezierTo(20, 34, 18, 32)
          ..lineTo(8, 22)
          ..quadraticBezierTo(6, 20, 8, 18)
          ..lineTo(18, 8)
          ..quadraticBezierTo(19, 6, 20, 6)
          ..close();
        final marked = symbol == MapSymbol.marked;
        canvas.drawPath(
          diamond,
          paint..color = marked ? visuals.marked : visuals.ground,
        );
        if (marked) {
          canvas.drawCircle(
            const Offset(20, 20),
            3,
            Paint()..color = visuals.ground,
          );
        } else {
          canvas.drawPath(
            diamond,
            Paint()
              ..color = visuals.route
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
        }
      case MapSymbol.routeArrow:
        canvas.drawPath(
          Path()
            ..moveTo(5, 6)
            ..lineTo(10, 8)
            ..lineTo(5, 10),
          Paint()
            ..color = visuals.arrow
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) =>
      symbol != old.symbol || visuals.scheme != old.visuals.scheme;
}
