// S1's second participant (D-033): joins a relay room in Firebase Realtime
// Database from this computer, sends a message every 10 s like the phone's
// test build, and reports how long messages take each way.
//
//   dart run tool/relay_peer.dart <room> [--minutes 20]
//
// Reads the project from android/app/google-services.json (not in git) and
// signs in anonymously. Messages carry a number, the send time on the
// server's clock and 96 random bytes: no location. At the end it prints the
// median and 95th percentile delay of the phone's messages.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/relay_peer.dart <room> [--minutes N]');
    exit(64);
  }
  final room = args.first;
  final i = args.indexOf('--minutes');
  final minutes = i >= 0 ? int.parse(args[i + 1]) : 20;

  final settings =
      jsonDecode(File('android/app/google-services.json').readAsStringSync())
          as Map<String, dynamic>;
  final database = settings['project_info']['firebase_url'] as String;
  final key = settings['client'][0]['api_key'][0]['current_key'] as String;

  final client = HttpClient();
  Future<Map<String, dynamic>> send(
    String method,
    Uri uri, [
    Object? body,
  ]) async {
    final request = await client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('User-Agent', 'Tripping S1 peer');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} $text', uri: uri);
    }
    return text == 'null' ? {} : jsonDecode(text) as Map<String, dynamic>;
  }

  final account = await send(
    'POST',
    Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$key',
    ),
    {'returnSecureToken': true},
  );
  final token = account['idToken'] as String;
  final me = account['localId'] as String;
  Uri at(String path) => Uri.parse('$database/s1/$room$path.json?auth=$token');
  void log(String line) =>
      stdout.writeln('PEER ${DateTime.now().toUtc().toIso8601String()} $line');
  log('start uid=${me.substring(0, 6)}');

  // The server's clock minus ours, from the server time of our own writes.
  final offsets = <int>[];
  int offset() {
    if (offsets.isEmpty) return 0;
    final sorted = [...offsets]..sort();
    return sorted[sorted.length ~/ 2];
  }

  int serverNow() => DateTime.now().millisecondsSinceEpoch + offset();

  final delays = <int>[];
  void received(String from, Object? value) {
    if (from == me || value is! Map) return;
    final sent = (value['sent'] as num?)?.toInt();
    final server = (value['server'] as num?)?.toInt();
    if (sent == null || server == null) return;
    final now = serverNow();
    delays.add(now - sent);
    log(
      'recv from=${from.substring(0, min(6, from.length))} '
      'seq=${value['seq']} e2e_ms=${now - sent} down_ms=${now - server}',
    );
  }

  // Server-sent events: a "put" of the whole room, then one per change.
  final stream = await client.getUrl(at(''));
  stream.headers.set('Accept', 'text/event-stream');
  final events = await stream.close();
  var event = '';
  final listening = events
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line.startsWith('event: ')) {
          event = line.substring(7);
        } else if (line.startsWith('data: ') &&
            (event == 'put' || event == 'patch')) {
          final data = jsonDecode(line.substring(6));
          if (data is! Map) return;
          final path = data['path'] as String;
          final value = data['data'];
          if (path == '/' && value is Map) {
            for (final entry in value.entries) {
              received(entry.key as String, entry.value);
            }
          } else {
            received(path.split('/')[1], value);
          }
        } else if (event == 'cancel' || event == 'auth_revoked') {
          log('stream ended: $event');
        }
      });

  final random = Random.secure();
  var seq = 0;
  final ticker = Timer.periodic(const Duration(seconds: 10), (_) async {
    final n = ++seq;
    final before = DateTime.now().millisecondsSinceEpoch;
    try {
      final written = await send('PUT', at('/$me'), {
        'seq': n,
        'sent': serverNow(),
        'server': {'.sv': 'timestamp'},
        'pad': base64Encode([for (var i = 0; i < 96; i++) random.nextInt(256)]),
      });
      final after = DateTime.now().millisecondsSinceEpoch;
      final server = (written['server'] as num).toInt();
      offsets.add(server - (before + after) ~/ 2);
      log('sent seq=$n ack_ms=${after - before}');
    } on Object catch (error) {
      log('send seq=$n failed: $error');
    }
  });

  await Future<void>.delayed(Duration(minutes: minutes));
  ticker.cancel();
  await listening.cancel();
  client.close(force: true);
  delays.sort();
  if (delays.isEmpty) {
    log('summary: nothing received');
  } else {
    int at(double q) =>
        delays[min(delays.length - 1, (q * delays.length).floor())];
    log(
      'summary: received=${delays.length} median_ms=${at(0.5)} '
      'p95_ms=${at(0.95)} max_ms=${delays.last} clock_offset_ms=${offset()}',
    );
  }
  exit(0);
}
