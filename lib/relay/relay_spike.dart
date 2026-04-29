import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// S1: can two devices on different networks exchange a message every 10 s
/// through Firebase Realtime Database, with what delay, and do they recover
/// after losing the network? (D-033.)
///
/// Only with `--dart-define=TRIPPING_RELAY_SPIKE=<room>`, where the room is
/// a long random name both sides know. Each message carries a number, the
/// send time on the server's clock, and 96 random bytes standing in for an
/// encrypted position: no location ever leaves the phone. Results go to the
/// log as `S1 …` lines.
abstract final class RelaySpike {
  static const room = String.fromEnvironment('TRIPPING_RELAY_SPIKE');
  static bool get enabled => room.isNotEmpty;

  static const _every = Duration(seconds: 10);

  static Future<void> start() async {
    await Firebase.initializeApp();
    final user = (await FirebaseAuth.instance.signInAnonymously()).user!;
    final db = FirebaseDatabase.instance;
    final me = user.uid;
    _log('start uid=${_short(me)}');

    // The server's clock minus ours, so both sides time on the same clock.
    var offset = 0;
    db.ref('.info/serverTimeOffset').onValue.listen((event) {
      offset = (event.snapshot.value as num?)?.toInt() ?? 0;
    });
    db.ref('.info/connected').onValue.listen((event) {
      _log('connected=${event.snapshot.value}');
    });
    int serverNow() => DateTime.now().millisecondsSinceEpoch + offset;

    void received(DatabaseEvent event) {
      final from = event.snapshot.key;
      final value = event.snapshot.value;
      if (from == null || from == me || value is! Map) return;
      final sent = (value['sent'] as num?)?.toInt();
      final server = (value['server'] as num?)?.toInt();
      if (sent == null || server == null) return;
      final now = serverNow();
      _log(
        'recv from=${_short(from)} seq=${value['seq']} '
        'e2e_ms=${now - sent} down_ms=${now - server}',
      );
    }

    final roomRef = db.ref('s1/$room');
    roomRef.onChildAdded.listen(received);
    roomRef.onChildChanged.listen(received);

    final random = Random.secure();
    var seq = 0;
    Timer.periodic(_every, (_) async {
      final n = ++seq;
      final sent = serverNow();
      final watch = Stopwatch()..start();
      try {
        await roomRef.child(me).set({
          'seq': n,
          'sent': sent,
          'server': ServerValue.timestamp,
          'pad': base64Encode([
            for (var i = 0; i < 96; i++) random.nextInt(256),
          ]),
        });
        _log('sent seq=$n ack_ms=${watch.elapsedMilliseconds}');
      } on Object catch (error) {
        _log('send seq=$n failed: $error');
      }
    });
  }

  static String _short(String uid) => uid.substring(0, min(6, uid.length));

  static void _log(String line) =>
      debugPrint('S1 ${DateTime.now().toUtc().toIso8601String()} $line');
}
