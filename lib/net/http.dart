import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Identifies the app to every open service it uses, as their terms ask.
const appUserAgent = 'Tripping/1.0 (Android; com.example.tripping)';

/// A server's answer: status and body.
typedef HttpAnswer = ({int status, String body});

/// Fetches a URL; injected so tests need no network.
typedef Fetch = Future<HttpAnswer> Function(Uri uri);

/// Thrown when there is no answer at all: no connection, no DNS, timeout.
class NoConnection implements Exception {
  const NoConnection();
}

/// GET with the app's User-Agent and a timeout. Any failure to reach the
/// server is a [NoConnection].
Future<HttpAnswer> httpGet(
  Uri uri, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final client = HttpClient()
    ..userAgent = appUserAgent
    ..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return (status: response.statusCode, body: body);
  } on SocketException {
    throw const NoConnection();
  } on TimeoutException {
    throw const NoConnection();
  } on HttpException {
    throw const NoConnection();
  } on HandshakeException {
    throw const NoConnection();
  } finally {
    client.close(force: true);
  }
}
