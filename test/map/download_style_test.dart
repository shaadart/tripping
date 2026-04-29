import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/map/download_style.dart';

Future<(int, String)> get(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  } finally {
    client.close();
  }
}

void main() {
  test(
    'serves the style on the loopback address while the work runs',
    () async {
      late String served;
      final (status, body) = await withLocalStyle('{"version":8}', (url) async {
        served = url;
        expect(url, startsWith('http://127.0.0.1:'));
        return get(url);
      });
      expect((status, body), (200, '{"version":8}'));
      expect(
        () => get(served),
        throwsA(isA<SocketException>()),
        reason: 'the server stops with the work',
      );
    },
  );

  test('serves nothing else', () async {
    await withLocalStyle('{}', (url) async {
      final (status, _) = await get(url.replaceFirst('style.json', 'other'));
      expect(status, 404);
    });
  });

  test('stops even when the work fails', () async {
    late String served;
    await expectLater(
      withLocalStyle('{}', (url) async {
        served = url;
        throw StateError('download failed');
      }),
      throwsStateError,
    );
    await expectLater(get(served), throwsA(isA<SocketException>()));
  });
}
