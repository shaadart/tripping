/// A place to go: from search, from the map, or from recent destinations.
class Place {
  const Place({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.detail,
  });

  final String name;

  /// Where it is, in words: "Bengaluru, Karnataka, India".
  final String? detail;
  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.name == name &&
      other.detail == detail &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(name, detail, latitude, longitude);

  @override
  String toString() => 'Place($name, $detail)';
}
