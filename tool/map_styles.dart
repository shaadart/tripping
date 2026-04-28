// Generates Tripping's three bundled map styles from OpenFreeMap's Positron
// and Dark (tool/map_styles/, unchanged upstream copies), so the changes are
// reproducible rather than hand edits:
//
// - light: greys warmed towards the app's paper, a softer blue water
// - dark: greys warmed towards the app's night, water kept visibly blue
// - sun: from Positron, darker roads and near-black labels for glare
//
//   dart run tool/map_styles.dart
//
// Only colours change; layers, sources and attribution stay as upstream.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main() {
  final positron = _read('positron');
  final dark = _read('dark');
  _write('light', _transform(positron, _light));
  _write('dark', _transform(dark, _night));
  _write('sun', _transform(positron, _sun));
}

typedef _Rule = _Colour Function(String layer, String property, _Colour c);

// Every grey, the background included, keeps its lightness, so upstream's
// contrast between land, roads and buildings survives the warming.
_Colour _light(String layer, String property, _Colour c) => switch (layer) {
  'water' => _Colour.hex(0xBED3DA),
  'waterway' => _Colour.hex(0xA9C6D2),
  _ => c.isGrey ? c.warmed(hue: 38, saturation: 0.28) : c,
};

_Colour _night(String layer, String property, _Colour c) => switch (layer) {
  'water' => _Colour.hex(0x15212A),
  'waterway' => _Colour.hex(0x1C2B35),
  _ => c.isGrey ? c.warmed(hue: 35, saturation: 0.12) : c,
};

_Colour _sun(String layer, String property, _Colour c) {
  switch (layer) {
    case 'background':
      return _Colour.hex(0xFAF8F3);
    case 'water':
      return _Colour.hex(0xA7C6D3);
    case 'waterway':
      return _Colour.hex(0x8DB3C4);
  }
  if (property == 'text-color') {
    return c.isGrey ? _Colour.hex(0x1A1714, c.a) : c.withLightness(c.l * 0.7);
  }
  if (property == 'text-halo-color') return _Colour.hex(0xFFFFFF, 0.95);
  if (!c.isGrey) return c;
  final warm = c.warmed(hue: 35, saturation: 0.08);
  return property.startsWith('line')
      ? warm.withLightness(warm.l * 0.78)
      : warm.withLightness(warm.l * 0.97);
}

Map<String, Object?> _transform(Map<String, Object?> style, _Rule rule) {
  final copy = jsonDecode(jsonEncode(style)) as Map<String, Object?>;
  for (final layer in (copy['layers']! as List).cast<Map<String, Object?>>()) {
    final paint = layer['paint'] as Map<String, Object?>?;
    if (paint == null) continue;
    for (final property in paint.keys.toList()) {
      if (!property.contains('color')) continue;
      paint[property] = _mapColours(
        paint[property],
        (c) => rule(layer['id']! as String, property, c),
      );
    }
  }
  return copy;
}

/// Replaces every colour string in a value, including inside expressions.
Object? _mapColours(Object? value, _Colour Function(_Colour) f) =>
    switch (value) {
      final String s => _Colour.parse(s)?.let(f).css ?? s,
      final List<Object?> l => [for (final item in l) _mapColours(item, f)],
      final Map<String, Object?> m => {
        for (final e in m.entries) e.key: _mapColours(e.value, f),
      },
      _ => value,
    };

Map<String, Object?> _read(String name) =>
    jsonDecode(File('tool/map_styles/$name.json').readAsStringSync())
        as Map<String, Object?>;

void _write(String name, Map<String, Object?> style) {
  File('assets/map/$name.json').writeAsStringSync(jsonEncode(style));
  stdout.writeln('assets/map/$name.json');
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// A colour in HSL with alpha, all in 0..1 except hue in degrees.
class _Colour {
  _Colour(this.h, this.s, this.l, this.a);

  factory _Colour.hex(int rgb, [double a = 1]) => _Colour.rgb(
    (rgb >> 16 & 0xFF) / 255,
    (rgb >> 8 & 0xFF) / 255,
    (rgb & 0xFF) / 255,
    a,
  );

  factory _Colour.rgb(double r, double g, double b, double a) {
    final hi = [r, g, b].reduce(max), lo = [r, g, b].reduce(min);
    final l = (hi + lo) / 2;
    if (hi == lo) return _Colour(0, 0, l, a);
    final d = hi - lo;
    final s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo);
    final h = hi == r
        ? (g - b) / d + (g < b ? 6 : 0)
        : hi == g
        ? (b - r) / d + 2
        : (r - g) / d + 4;
    return _Colour(h * 60, s, l, a);
  }

  static final _rgb = RegExp(
    r'^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$',
  );
  static final _hsl = RegExp(
    r'^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$',
  );

  static _Colour? parse(String text) {
    final t = text.trim();
    if (RegExp(r'^#[0-9a-fA-F]{3}$').hasMatch(t)) {
      return _Colour.hex(
        int.parse(
          t.substring(1).split('').map((c) => '$c$c').join(),
          radix: 16,
        ),
      );
    }
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(t)) {
      return _Colour.hex(int.parse(t.substring(1), radix: 16));
    }
    if (_rgb.firstMatch(t) case final m?) {
      double at(int i) => double.parse(m.group(i)!) / 255;
      return _Colour.rgb(at(1), at(2), at(3), double.parse(m.group(4) ?? '1'));
    }
    if (_hsl.firstMatch(t) case final m?) {
      return _Colour(
        double.parse(m.group(1)!),
        double.parse(m.group(2)!) / 100,
        double.parse(m.group(3)!) / 100,
        double.parse(m.group(4) ?? '1'),
      );
    }
    return null;
  }

  final double h, s, l, a;

  bool get isGrey => s < 0.15;

  /// The same lightness, tinted towards [hue]; pure white and black stay.
  _Colour warmed({required double hue, required double saturation}) =>
      l >= 0.99 || l <= 0.01 ? this : _Colour(hue, saturation, l, a);

  _Colour withLightness(double lightness) =>
      _Colour(h, s, lightness.clamp(0, 1), a);

  String get css {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    final (r, g, b) = switch (h % 360 ~/ 60) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    int byte(double v) => ((v + m) * 255).round().clamp(0, 255);
    final alpha = a >= 1 ? '1' : a.toStringAsFixed(2);
    return 'rgba(${byte(r)},${byte(g)},${byte(b)},$alpha)';
  }
}
