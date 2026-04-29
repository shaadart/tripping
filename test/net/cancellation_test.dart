import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/net/http.dart';

void main() {
  test('cancelling a rate-limit wait removes its timer', () {
    fakeAsync((async) {
      final cancel = RequestCancellation();
      var stopped = false;
      cancel.delay(const Duration(minutes: 1)).catchError((Object error) {
        expect(error, isA<RequestCancelled>());
        stopped = true;
      });
      cancel.cancel();
      async.flushMicrotasks();
      expect(stopped, isTrue);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('cancelling HTTP closes a real pending loopback request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<void>();
    final closed = Completer<void>();
    server.listen((request) {
      received.complete();
      unawaited(
        request.response.done.then(
          (_) {
            if (!closed.isCompleted) closed.complete();
          },
          onError: (Object _) {
            if (!closed.isCompleted) closed.complete();
          },
        ),
      );
    });
    final cancel = RequestCancellation();
    final answer = httpGet(
      Uri.parse('http://127.0.0.1:${server.port}/synthetic'),
      cancellation: cancel,
    );
    final cancelled = expectLater(answer, throwsA(isA<RequestCancelled>()));
    await received.future;
    cancel.cancel();
    await cancelled.timeout(const Duration(seconds: 2));
    // Force-close the server's unused response after verifying client abort.
    await server.close(force: true);
  });
}
