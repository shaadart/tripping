// A second group member on this computer, for G2 on one phone: joins the
// group of an invitation link, says "here" with a sealed name every 30 s,
// like the app, and prints whom it hears and how long ago.
//
//   dart run tool/group_peer.dart '<tripping://invite/join?…>' \
//       [--name 'Computer'] [--minutes 10]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tripping/group/group_keys.dart';
import 'package:tripping/group/invite.dart';

import 'src/firebase_rest.dart';

Future<void> main(List<String> args) async {
  final invite = args.isEmpty ? null : Invite.find(args.first);
  if (invite == null) {
    stderr.writeln(
      "usage: dart run tool/group_peer.dart '<invite link>' "
      '[--name N] [--minutes M]',
    );
    exit(64);
  }
  String option(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final name = option('name', 'Computer');
  final minutes = int.parse(option('minutes', '10'));
  final fb = FirebaseRest.fromSettings();
  final keys = await GroupKeys.derive(invite.secret);
  final (me, token) = await fb.signUp();
  final room = 'rooms/${keys.room}';
  void log(String line) =>
      stdout.writeln('PEER ${DateTime.now().toUtc().toIso8601String()} $line');

  final (joined, why) = await fb.call(
    'PUT',
    fb.at('$room/members/$me', token),
    {'joined': FirebaseRest.now},
  );
  log(
    'joined ${invite.hostName}\'s group: $joined${joined == 200 ? '' : ' $why'}',
  );
  if (joined != 200) exit(1);

  // The server's clock minus ours, from our own writes.
  var offset = 0;
  var seq = 0;
  Future<void> say() async {
    final before = DateTime.now().millisecondsSinceEpoch;
    final (status, body) = await fb.call(
      'PUT',
      fb.at('$room/presence/$me', token),
      {
        'seq': ++seq,
        'at': FirebaseRest.now,
        'box': await keys.seal({'name': name}, me),
      },
    );
    final after = DateTime.now().millisecondsSinceEpoch;
    if (status == 200) {
      final at = (jsonDecode(body) as Map)['at'] as int;
      offset = at - (before + after) ~/ 2;
    }
    log('said here seq=$seq: $status');
  }

  Future<void> heard(Map<Object?, Object?> presence) async {
    final now = DateTime.now().millisecondsSinceEpoch + offset;
    for (final MapEntry(:key, :value) in presence.entries) {
      if (key == me || value is! Map) continue;
      final message = await keys.open('${value['box']}', '$key');
      final at = value['at'];
      log(
        message == null || at is! int
            ? 'an entry that does not open (from ${'$key'.substring(0, 6)})'
            : 'heard ${message['name']} seq=${value['seq']} '
                  '${((now - at) / 1000).toStringAsFixed(1)} s ago',
      );
    }
  }

  // Server-sent events: the whole presence first, then each change.
  final request = await fb.client.getUrl(fb.at('$room/presence', token));
  request.headers.set('Accept', 'text/event-stream');
  final events = await request.close();
  var event = '';
  final listening = events
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) async {
        if (line.startsWith('event: ')) event = line.substring(7);
        if (!line.startsWith('data: ') || event != 'put') return;
        final data = jsonDecode(line.substring(6));
        if (data is! Map) return;
        final path = data['path'] as String;
        final value = data['data'];
        if (path == '/' && value is Map) {
          await heard(value);
        } else if (value is Map) {
          await heard({path.substring(1): value});
        }
      });

  await say();
  final ticker = Timer.periodic(const Duration(seconds: 30), (_) => say());
  await Future<void>.delayed(Duration(minutes: minutes));
  ticker.cancel();
  await listening.cancel();
  // Leave, as a member would: the group goes on.
  await fb.call('DELETE', fb.at('$room/presence/$me', token));
  await fb.call('DELETE', fb.at('$room/members/$me', token));
  log('left');
  fb.client.close(force: true);
  exit(0);
}
