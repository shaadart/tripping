import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'relay.dart';

/// [Relay] over Firebase Realtime Database (D-034), laid out as the rules
/// in `firebase/database.rules.json` expect:
///
/// - `rooms/<room>/meta`: written once, by whoever creates the room
/// - `rooms/<room>/members/<uid>`: each member's own join
/// - `rooms/<room>/presence/<uid>`: each member's latest entry
///
/// Sign-in is anonymous: the uid is this install's identity at the relay.
class FirebaseRelay implements Relay {
  Future<void>? _ready;

  Future<void> _start() => _ready ??= () async {
    try {
      await Firebase.initializeApp();
      // Positions are latest-only: nothing waits on the phone to be sent.
      FirebaseDatabase.instance.setPersistenceEnabled(false);
    } on Object {
      _ready = null;
      throw const RelayUnavailable(
        'Group sharing is not set up in this build of Tripping',
      );
    }
  }();

  @override
  Future<String> me() async {
    await _start();
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    if (user == null) throw const RelayUnavailable('Could not sign in');
    return user.uid;
  }

  @override
  Future<RelayRoom> open(String room, {required bool create}) async {
    final uid = await me();
    final db = FirebaseDatabase.instance;
    final ref = db.ref('rooms/$room');
    if (create) {
      try {
        await ref.child('meta').set({
          'created': ServerValue.timestamp,
          'by': uid,
        });
      } on FirebaseException {
        // Already made (an earlier start of this journey): fine.
      }
    }
    return _FirebaseRoom(db, ref, uid);
  }
}

class _FirebaseRoom implements RelayRoom {
  _FirebaseRoom(this._db, this._ref, this._uid) {
    _offsetWatch = _db.ref('.info/serverTimeOffset').onValue.listen((event) {
      _offset = Duration(
        milliseconds: (event.snapshot.value as num?)?.toInt() ?? 0,
      );
    });
  }

  final FirebaseDatabase _db;
  final DatabaseReference _ref;
  final String _uid;
  StreamSubscription<DatabaseEvent>? _offsetWatch;
  Duration _offset = Duration.zero;
  bool _joined = false;

  /// Only members may read the room: listening waits for the join.
  final _member = Completer<void>();

  @override
  Duration get clockOffset => _offset;

  @override
  Stream<bool> get connected =>
      _db.ref('.info/connected').onValue.asyncMap((event) async {
        final up = event.snapshot.value == true;
        if (!up) {
          // Whatever did not go out is stale by the time it could.
          await _db.purgeOutstandingWrites();
        } else if (!_joined) {
          await _join();
        }
        return up;
      });

  Future<void> _join() async {
    try {
      await _ref.child('members/$_uid').set({'joined': ServerValue.timestamp});
      _joined = true;
      if (!_member.isCompleted) _member.complete();
    } on FirebaseException {
      // Not allowed (no such room yet): the next connection tries again.
    }
  }

  @override
  Stream<List<RelayEntry>> get entries async* {
    await _member.future;
    yield* _ref.child('presence').onValue.map(_entriesOf);
  }

  static List<RelayEntry> _entriesOf(DatabaseEvent event) {
    final value = event.snapshot.value;
    if (value is! Map) return const [];
    return [
      for (final MapEntry(:key, :value) in value.entries)
        if (value case {
          'seq': final num seq,
          'at': final num at,
          'box': final String box,
        })
          RelayEntry(
            participant: '$key',
            seq: seq.toInt(),
            at: DateTime.fromMillisecondsSinceEpoch(at.toInt(), isUtc: true),
            box: box,
          ),
    ];
  }

  @override
  Future<void> publish(int seq, String box) async {
    if (!_joined) await _join();
    await _ref.child('presence/$_uid').set({
      'seq': seq,
      'at': ServerValue.timestamp,
      'box': box,
    });
  }

  @override
  Stream<bool> get ended async* {
    await _member.future;
    yield* _ref
        .child('meta/closed')
        .onValue
        .map((event) => event.snapshot.value != null);
  }

  @override
  Future<void> leave() async {
    await _ref.child('presence/$_uid').remove();
    await _ref.child('members/$_uid').remove();
  }

  @override
  Future<void> close() async {
    await _offsetWatch?.cancel();
  }
}
