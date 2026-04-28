import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/net/http.dart';
import 'package:tripping/places/place.dart';
import 'package:tripping/places/place_search.dart';

Map<String, Object?> feature(
  Map<String, Object?> properties,
  double longitude,
  double latitude,
) => {
  'type': 'Feature',
  'properties': properties,
  'geometry': {
    'type': 'Point',
    'coordinates': [longitude, latitude],
  },
};

void main() {
  final answer = jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      feature(
        {
          'name': 'Cubbon Park',
          'city': 'Bengaluru',
          'state': 'Karnataka',
          'country': 'India',
        },
        77.5922,
        12.9743,
      ),
      // The same place again, as Photon sometimes answers.
      feature(
        {
          'name': 'Cubbon Park',
          'city': 'Bengaluru',
          'state': 'Karnataka',
          'country': 'India',
        },
        77.5923,
        12.9744,
      ),
      feature(
        {'street': 'Kasturba Road', 'housenumber': '12', 'city': 'Bengaluru'},
        77.59,
        12.97,
      ),
      feature({'city': 'Nameless'}, 77, 12),
    ],
  });

  test('reads names, places and positions, without repeats', () {
    expect(placesFromPhoton(jsonDecode(answer)), [
      const Place(
        name: 'Cubbon Park',
        detail: 'Bengaluru, Karnataka, India',
        latitude: 12.9743,
        longitude: 77.5922,
      ),
      const Place(
        name: 'Kasturba Road 12',
        detail: 'Bengaluru',
        latitude: 12.97,
        longitude: 77.59,
      ),
    ]);
  });

  test('asks with the text and, when known, the position to favour', () async {
    final asked = <Uri>[];
    final search = PhotonSearch(
      baseUrl: 'https://photon.test',
      fetch: (uri) async {
        asked.add(uri);
        return (status: 200, body: answer);
      },
    );
    final places = await search.search(
      ' cubbon ',
      nearLatitude: 12.97631,
      nearLongitude: 77.59291,
    );
    expect(places, hasLength(2));
    expect(asked.single.host, 'photon.test');
    expect(asked.single.queryParameters, {
      'q': 'cubbon',
      'limit': '8',
      'lang': 'en',
      'lat': '12.9763',
      'lon': '77.5929',
    });
  });

  test('too short a query is not sent at all', () async {
    final search = PhotonSearch(
      fetch: (_) async => fail('should not have been asked'),
    );
    expect(await search.search('cu'), isEmpty);
  });

  test('without a connection it says so, and that the map still works', () {
    final search = PhotonSearch(fetch: (_) async => throw const NoConnection());
    expect(
      search.search('cubbon'),
      throwsA(isA<SearchError>().having((e) => e.offline, 'offline', isTrue)),
    );
  });

  test('a failing or garbled service is an error, not empty results', () {
    expect(
      PhotonSearch(
        fetch: (_) async => (status: 503, body: 'busy'),
      ).search('cubbon'),
      throwsA(isA<SearchError>().having((e) => e.offline, 'offline', isFalse)),
    );
    expect(
      PhotonSearch(
        fetch: (_) async => (status: 200, body: '<html>'),
      ).search('cubbon'),
      throwsA(isA<SearchError>()),
    );
  });
}
