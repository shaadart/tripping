import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Identifies the app to every open service it uses, as their terms ask.
const appUserAgent = 'Tripping/1.0 (Android; com.shaadart.tripping)';

/// A server's answer: status and body.
typedef HttpAnswer = ({int status, String body});

/// Fetches a URL; injected so tests need no network.
typedef Fetch = Future<HttpAnswer> Function(Uri uri);

/// Thrown when there is no answer at all: no connection, no DNS, timeout.
class NoConnection implements Exception {
  const NoConnection();
}

/// A request/spacing wait cancelled by full pause; never a route failure.
class RequestCancelled implements Exception {
  const RequestCancelled();
}

class RequestCancellation {
  bool _cancelled = false;
  final _abort = <void Function()>{};

  void check() {
    if (_cancelled) throw const RequestCancelled();
  }

  void cancel() {
    _cancelled = true;
    for (final abort in List.of(_abort)) {
      abort();
    }
    _abort.clear();
  }

  Future<void> delay(Duration duration) async {
    check();
    if (duration <= Duration.zero) return;
    final done = Completer<void>();
    final timer = Timer(duration, () => done.complete());
    void abort() {
      timer.cancel();
      if (!done.isCompleted) done.completeError(const RequestCancelled());
    }

    _abort.add(abort);
    try {
      await done.future;
    } finally {
      _abort.remove(abort);
      timer.cancel();
    }
    check();
  }
}

/// GET with the app's User-Agent and a timeout. Any failure to reach the
/// server is a [NoConnection].
Future<HttpAnswer> httpGet(
  Uri uri, {
  Duration timeout = const Duration(seconds: 12),
  RequestCancellation? cancellation,
}) async {
  cancellation?.check();
  final client = HttpClient()
    ..userAgent = appUserAgent
    ..connectionTimeout = timeout;
  void abort() => client.close(force: true);
  cancellation?._abort.add(abort);
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    cancellation?.check();
    return (status: response.statusCode, body: body);
  } on SocketException {
    cancellation?.check();
    throw const NoConnection();
  } on TimeoutException {
    throw const NoConnection();
  } on HttpException {
    cancellation?.check();
    throw const NoConnection();
  } on HandshakeException {
    throw const NoConnection();
  } finally {
    cancellation?._abort.remove(abort);
    client.close(force: true);
  }
}
