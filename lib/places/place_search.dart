import 'dart:convert';

import '../net/http.dart';
import 'place.dart';

/// Why a search shows no results.
class SearchError implements Exception {
  const SearchError(this.message, {this.offline = false});

  final String message;

  /// True when there was no connection: the map can still be used instead.
  final bool offline;

  @override
  String toString() => message;
}

/// Finds places by name.
abstract interface class PlaceSearch {
  /// Places matching [query], those near the given position first. Throws a
  /// [SearchError].
  Future<List<Place>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
  });
}

/// Photon: open-source search over OpenStreetMap, made for search as you
/// type (D-026). The public instance asks for fair use; the address is a
/// build setting so another instance can replace it.
class PhotonSearch implements PlaceSearch {
  PhotonSearch({this.baseUrl = defaultUrl, Fetch? fetch})
    : _fetch = fetch ?? httpGet;

  static const defaultUrl = String.fromEnvironment(
    'TRIPPING_SEARCH_URL',
    defaultValue: 'https://photon.komoot.io',
  );

  /// Shorter queries match too much to be useful, and cost the service.
  static const minLength = 3;

  final String baseUrl;
  final Fetch _fetch;

  @override
  Future<List<Place>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
  }) async {
    final text = query.trim();
    if (text.length < minLength) return const [];
    final uri = Uri.parse('$baseUrl/api/').replace(
      queryParameters: {
        'q': text,
        'limit': '8',
        'lang': 'en',
        if (nearLatitude != null && nearLongitude != null) ...{
          'lat': nearLatitude.toStringAsFixed(4),
          'lon': nearLongitude.toStringAsFixed(4),
        },
      },
    );
    final HttpAnswer answer;
    try {
      answer = await _fetch(uri);
    } on NoConnection {
      throw const SearchError('Search needs a connection.', offline: true);
    }
    if (answer.status != 200) {
      throw SearchError(
        'The search service is not answering (${answer.status}). Try again '
        'later.',
      );
    }
    try {
      return placesFromPhoton(jsonDecode(answer.body));
    } on FormatException {
      throw const SearchError('The search service sent something unreadable.');
    }
  }
}

/// Places from Photon's GeoJSON answer, without duplicates.
List<Place> placesFromPhoton(Object? json) {
  if (json is! Map || json['features'] is! List) {
    throw const FormatException('Not a Photon answer');
  }
  final places = <Place>[];
  for (final feature
      in (json['features'] as List).whereType<Map<Object?, Object?>>()) {
    final properties = feature['properties'];
    final geometry = feature['geometry'];
    if (properties is! Map || geometry is! Map) continue;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) continue;
    String? text(String key) => switch (properties[key]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    final street = [
      text('street'),
      text('housenumber'),
    ].whereType<String>().join(' ');
    final name = text('name') ?? (street.isEmpty ? null : street);
    if (name == null) continue;
    final parts = <String>[];
    for (final key in ['city', 'county', 'state', 'country']) {
      final part = text(key);
      if (part != null && part != name && !parts.contains(part)) {
        parts.add(part);
      }
    }
    final place = Place(
      name: name,
      detail: parts.isEmpty ? null : parts.join(', '),
      latitude: (coordinates[1] as num).toDouble(),
      longitude: (coordinates[0] as num).toDouble(),
    );
    final repeat = places.any(
      (p) => p.name == place.name && p.detail == place.detail,
    );
    if (!repeat) places.add(place);
  }
  return places;
}
