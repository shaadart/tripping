import 'dart:async';
import 'dart:io';

/// Runs [work] with [style] served at a local address, on this phone only.
///
/// MapLibre's offline downloader fetches its style over HTTP and cannot read
/// a file (E-023). Serving the app's own style lets a saved area hold what
/// the maps draw, terrain included, instead of only what a hosted style
/// lists. The server listens on the loopback address alone, and only while
/// [work] runs.
Future<T> withLocalStyle<T>(
  String style,
  Future<T> Function(String url) work,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    final response = request.response;
    if (request.method == 'GET' && request.uri.path == '/style.json') {
      response.headers.contentType = ContentType.json;
      response.write(style);
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    unawaited(response.close());
  });
  try {
    return await work('http://127.0.0.1:${server.port}/style.json');
  } finally {
    await server.close(force: true);
  }
}
