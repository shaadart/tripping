// A second group member on this computer, for G2 and G3 on one phone:
// joins the group of an invitation link, tells it every 30 s, like an
// expedition, that it stands at Ooty Lake (a public place, never this
// computer's location), and prints what it hears: name, phase, distance
// from the lake and age.
//
//   dart run tool/group_peer.dart '<tripping://invite/join?…>' \
//       [--name 'Computer'] [--minutes 10] [--at lat,lon] [--emulator]
//       [--walk metres] [--replay-after N]
//
// --at moves it elsewhere; use only public places. --emulator uses the local
// emulators instead of the project in google-services.json. It speaks the
// sealed session/counter protocol (D-059): --walk moves it north each time
// it speaks; --replay-after N puts its own first box back after N messages,
// as a replaying relay would, to show the phone refuses it. It prints which
// of its messages the phone says it has.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tripping/group/group_keys.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/group/sharing.dart';
import 'package:tripping/journey/journey.dart';

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
  final [atLat, atLon] = [
    for (final part in option('at', '${_lake.$1},${_lake.$2}').split(','))
      double.parse(part),
  ];
  final fb = args.contains('--emulator')
      ? FirebaseRest.emulator()
      : FirebaseRest.fromSettings();
  final walk = double.parse(option('walk', '0'));
  final replayAfter = int.parse(option('replay-after', '0'));
  final session = base64Url
      .encode([for (var i = 0; i < 8; i++) Random.secure().nextInt(256)])
      .replaceAll('=', '');
  var counter = 0;
  String? firstBox;
  final sentAt = <int, DateTime>{};
  // The phone's newest accepted message, as a receipt to send back.
  final receipts = <String, Object?>{};
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
    final now = DateTime.now().toUtc();
    final c = ++counter;
    final north = walk * (c - 1);
    final box = await keys.seal({
      ...Shared(
        name: name,
        phase: JourneyPhase.recording,
        mode: JourneyMode.expedition,
        fix: Fix(
          time: now,
          latitude: atLat + north / 111195.08,
          longitude: atLon,
          accuracy: 5,
        ),
        fixArrivedAt: now,
      ).toMessage(at: now),
      'q': [session, c],
      't': now.millisecondsSinceEpoch ~/ 1000,
      if (receipts.isNotEmpty) 'r': receipts,
    }, me);
    firstBox ??= box;
    final (status, body) = await fb.call(
      'PUT',
      fb.at('$room/presence/$me', token),
      {'seq': ++seq, 'at': FirebaseRest.now, 'box': box},
    );
    final after = DateTime.now().millisecondsSinceEpoch;
    if (status == 200) {
      final at = (jsonDecode(body) as Map)['at'] as int;
      offset = at - (before + after) ~/ 2;
      sentAt[c] = now;
    }
    log('said counter=$c ${north.round()} m north seq=$seq: $status');
    if (replayAfter > 0 && c == replayAfter) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final (replayed, _) = await fb.call(
        'PUT',
        fb.at('$room/presence/$me', token),
        {'seq': ++seq, 'at': FirebaseRest.now, 'box': firstBox},
      );
      log('REPLAYED counter=1 box with a new relay time, seq=$seq: $replayed');
    }
  }

  Future<void> heard(Map<Object?, Object?> presence) async {
    final now = DateTime.now().millisecondsSinceEpoch + offset;
    for (final MapEntry(:key, :value) in presence.entries) {
      if (key == me || value is! Map) continue;
      final message = await keys.open('${value['box']}', '$key');
      final shared = message == null ? null : Shared.fromMessage(message);
      final at = value['at'];
      if (shared == null || at is! int) {
        log('an entry that does not open (from ${'$key'.substring(0, 6)})');
        continue;
      }
      if (message!['q'] case [final String s, final int c]) {
        receipts['$key'.length <= 8 ? '$key' : '$key'.substring(0, 8)] = [
          s.substring(0, 4),
          c,
        ];
      }
      final mine = me.length <= 8 ? me : me.substring(0, 8);
      if (message['r'] case final Map<String, Object?> told) {
        if (told[mine] case [
          final String s,
          final int c,
        ] when s == session.substring(0, 4)) {
          log('the phone says it has counter=$c (sent ${sentAt[c]})');
        }
      }
      final fix = shared.fix;
      final lake = Fix(time: DateTime.now(), latitude: atLat, longitude: atLon);
      log(
        'heard ${shared.name} seq=${value['seq']} ${shared.phase.name} '
        '${shared.mode.name} '
        '${fix == null ? 'no position' : '${distanceAndDirection(lake, fix)} from here, fix ${((now - fix.time.millisecondsSinceEpoch) / 1000).round()} s old'}, '
        'received ${((now - at) / 1000).toStringAsFixed(1)} s ago',
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
  // The last one out removes the room; the rules refuse while anyone stays.
  final (gone, _) = await fb.call('DELETE', fb.at('$room/meta', token));
  log('room removed: ${gone == 200 ? 'yes' : 'no ($gone): others remain'}');
  fb.client.close(force: true);
  exit(0);
}

/// Ooty Lake, a public place: where this test member says it is.
const _lake = (11.4065, 76.6872);
