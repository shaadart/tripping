/// Decodes an encoded polyline (Google's format, as Valhalla returns it with
/// six decimal places) into latitude and longitude pairs.
List<(double, double)> decodePolyline(String encoded, {int precision = 6}) {
  final factor = _pow10(precision);
  final points = <(double, double)>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;
  int next() {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      if (index >= encoded.length) {
        throw const FormatException('Polyline ends in the middle of a value');
      }
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    latitude += next();
    longitude += next();
    points.add((latitude / factor, longitude / factor));
  }
  return points;
}

/// Encodes latitude and longitude pairs as a polyline, the inverse of
/// [decodePolyline]; used to store routes compactly.
String encodePolyline(List<(double, double)> points, {int precision = 6}) {
  final factor = _pow10(precision);
  final out = StringBuffer();
  var previousLatitude = 0;
  var previousLongitude = 0;
  void write(int value) {
    var v = value < 0 ? ~(value << 1) : value << 1;
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
  }

  for (final (latitude, longitude) in points) {
    final lat = (latitude * factor).round();
    final lon = (longitude * factor).round();
    write(lat - previousLatitude);
    write(lon - previousLongitude);
    previousLatitude = lat;
    previousLongitude = lon;
  }
  return out.toString();
}

int _pow10(int n) {
  var value = 1;
  for (var i = 0; i < n; i++) {
    value *= 10;
  }
  return value;
}
