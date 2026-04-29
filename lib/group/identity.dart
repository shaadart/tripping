import 'dart:convert';

import 'package:characters/characters.dart';

enum IdentityColour {
  clay('Clay', 0xFFA64526),
  river('River', 0xFF17647C),
  moss('Moss', 0xFF3C623C),
  plum('Plum', 0xFF744D7F),
  ochre('Ochre', 0xFF805D18),
  slate('Slate', 0xFF43566D);

  const IdentityColour(this.label, this.argb);
  final String label;
  final int argb;
  static IdentityColour parse(Object? value) =>
      values.firstWhere((colour) => colour.name == value, orElse: () => clay);
}

/// Original silhouettes inspired by ancient signs/seals, not translations.
enum MarkerShape {
  rosette('Rosette'),
  reed('Reed'),
  gate('Gate'),
  tablet('Tablet');

  const MarkerShape(this.label);
  final String label;
  static MarkerShape parse(Object? value) =>
      values.firstWhere((shape) => shape.name == value, orElse: () => tablet);
}

class MapIdentity {
  const MapIdentity({
    this.name = 'Traveller',
    this.colour = IdentityColour.clay,
    this.shape = MarkerShape.tablet,
  });
  final String name;
  final IdentityColour colour;
  final MarkerShape shape;

  String get displayName =>
      cleanName(name).isEmpty ? 'Traveller' : cleanName(name);
  String get initials {
    final words = displayName.split(' ');
    return (words.first.characters.first +
            (words.length > 1 ? words.last.characters.first : ''))
        .toUpperCase();
  }

  String get description => '$displayName, ${colour.label}, ${shape.label}';

  static const nameLength = 40;
  static String cleanName(String value) {
    final line = value
        .replaceAll(RegExp(r'[\s\x00-\x1f\x7f-\x9f]+'), ' ')
        .trim();
    final out = StringBuffer();
    var bytes = 0;
    for (final char in line.characters.take(nameLength)) {
      bytes += utf8.encode(char).length;
      if (bytes > 160) {
        break; // Keep sealed identity messages within relay bounds.
      }
      out.write(char);
    }
    return out.toString().trim();
  }
}

String identityMarkerKey(MapIdentity identity, {bool hollow = false}) =>
    'identity-${identity.colour.name}-${identity.shape.name}-'
    '${base64Url.encode(utf8.encode(identity.initials))}-${hollow ? 'old' : 'live'}';
