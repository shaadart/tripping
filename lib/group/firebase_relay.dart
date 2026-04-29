import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'relay.dart';
import 'group_auth.dart';

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
  bool _active = false;
  int _epoch = 0;
  String? _uid;

  @override
  Future<void> resume() async {
    final epoch = ++_epoch;
    _active = true;
    await _start();
    _uid = await GroupAuth.change('restore');
    if (!_active) await GroupAuth.change('park');
    if (_active && epoch == _epoch) await FirebaseDatabase.instance.goOnline();
  }

  @override
  Future<void> suspend() async {
    final epoch = ++_epoch;
    _active = false;
    // A paused cold start never initialises Firebase or anonymous auth.
    final ready = _ready;
    if (ready == null) return;
    try {
      await ready;
    } on RelayUnavailable {
      // There was no configured transport to stop.
      return;
    }
    if (epoch != _epoch) return;
    await FirebaseDatabase.instance.goOffline();
    if (epoch != _epoch) return;
    try {
      await FirebaseDatabase.instance.purgeOutstandingWrites();
    } finally {
      await GroupAuth.change('park');
      _uid = null;
    }
  }

  void _requireActive() {
    if (!_active) throw const RelayUnavailable('Group updates are paused');
  }

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
    _requireActive();
    await _start();
    _requireActive();
    if (_uid case final uid?) return uid;
    final auth = FirebaseAuth.instance;
    User? user;
    try {
      user = auth.currentUser ?? (await auth.signInAnonymously()).user;
    } on FirebaseAuthException {
      throw const RelayUnavailable('Could not connect to group sign-in');
    }
    final preserved = await GroupAuth.change('remember');
    if (!_active) await GroupAuth.change('park');
    _requireActive();
    if (user == null) throw const RelayUnavailable('Could not sign in');
    return _uid = preserved ?? user.uid;
  }

  @override
  Future<RelayRoom> open(String room, {required bool create}) async {
    final uid = await me();
    _requireActive();
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
    _requireActive();
    return _FirebaseRoom(db, ref, uid);
  }

  @override
  Future<void> leaveRoom(String room) async {
    // Initialise Firebase before accessing its default database. Startup
    // housekeeping can be the first operation after opening the app.
    final uid = await me();
    await _leave(FirebaseDatabase.instance.ref('rooms/$room'), uid);
  }
}

/// Own entries out, then the room itself if no one is left; the rules
/// refuse that last step while anyone remains.
Future<void> _leave(DatabaseReference room, String uid) async {
  await room.child('presence/$uid').remove();
  await room.child('members/$uid').remove();
  try {
    await room.child('meta').remove();
  } on FirebaseException {
    // Others are still in it.
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
  bool _closed = false;

  /// Only members may read the room: listening waits for the join.
  final _member = Completer<void>();

  @override
  Duration get clockOffset => _offset;

  @override
  Stream<bool> get connected =>
      _db.ref('.info/connected').onValue.asyncMap((event) async {
        if (_closed) return false;
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
    if (_closed) return;
    try {
      await _ref.child('members/$_uid').set({'joined': ServerValue.timestamp});
      if (_closed) return;
      _joined = true;
      if (!_member.isCompleted) _member.complete();
    } on FirebaseException {
      // Not allowed (no such room yet): the next connection tries again.
    }
  }

  @override
  Stream<List<RelayEntry>> get entries async* {
    await _member.future;
    if (_closed) return;
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
    if (_closed) throw StateError('Room is closed');
    if (!_joined) await _join();
    if (_closed) throw StateError('Room is closed');
    await _ref.child('presence/$_uid').set({
      'seq': seq,
      'at': ServerValue.timestamp,
      'box': box,
    });
  }

  @override
  Stream<bool> get ended async* {
    await _member.future;
    if (_closed) return;
    yield* _ref
        .child('meta/closed')
        .onValue
        .map((event) => event.snapshot.value != null);
  }

  @override
  Future<void> leave() => _leave(_ref, _uid);

  @override
  Future<void> forget(String participant) async {
    await _ref.child('presence/$participant').remove();
    await _ref.child('members/$participant').remove();
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (!_member.isCompleted) _member.complete();
    await _offsetWatch?.cancel();
  }
}
