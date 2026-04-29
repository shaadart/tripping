import 'dart:async';

import 'package:flutter/foundation.dart';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import 'group_keys.dart';
import 'relay.dart';
import 'sharing.dart';

/// Someone else in the group, as last heard.
class Companion {
  const Companion({
    required this.participant,
    required this.heardAt,
    required this.shared,
  });

  final String participant;

  /// When the relay last received from them, on this phone's clock.
  final DateTime heardAt;

  /// What they last said: name, phase, mode and their newest saved fix.
  final Shared shared;

  String get name => shared.name;
}

/// What the screen may say about the group: reachable or not, who was heard
/// when and what they said. Never more.
class GroupStatus {
  const GroupStatus({
    this.connected = false,
    this.heard = false,
    this.ended = false,
    this.companions = const [],
    this.problem,
  });

  /// The relay is reachable now.
  final bool connected;

  /// The room's entries have been read at least once.
  final bool heard;

  /// The inviter ended the group: nothing more is shared.
  final bool ended;
  final List<Companion> companions;

  /// Why group sharing cannot work at all here.
  final String? problem;
}

/// Shares this phone's journey with its group (G2, G3): joins the room,
/// tells the group per [SharePolicy] while the relay is reachable, and
/// once on reconnecting, never queued; and turns the room's entries into
/// companions.
class GroupSync {
  GroupSync(
    this._relay, {
    this.tick = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final Relay _relay;
  final Duration tick;
  final DateTime Function() _clock;

  /// Null while the journey shown is in no group.
  final status = ValueNotifier<GroupStatus?>(null);

  String? _secret;
  GroupKeys? _keys;
  String? _me;
  RelayRoom? _room;
  final _listening = <StreamSubscription<Object?>>[];
  Timer? _ticker;
  var _connected = false;
  var _ended = false;
  var _seq = 0;
  var _generation = 0;
  Shared? _mine;
  Shared? _told;
  DateTime? _toldAt;
  Future<void>? _telling;

  /// What this phone has to say now; told when the policy says so.
  void update(Shared mine) {
    _mine = mine;
    unawaited(_tell());
  }

  /// Follows [membership]: joins its room, or leaves the current one when
  /// it is null or another.
  Future<void> follow(MembershipRow? membership) async {
    if (membership?.secret == _secret) return;
    // What there is to say stays: it may have arrived just before.
    await _leaveRoom();
    final generation = ++_generation;
    _secret = membership?.secret;
    if (membership == null) return;
    status.value = const GroupStatus();
    try {
      final keys = await GroupKeys.derive(membership.secret);
      final me = await _relay.me();
      final room = await _relay.open(
        keys.room,
        create: membership.role == GroupRole.creator,
      );
      if (generation != _generation) {
        await room.close();
        return;
      }
      _keys = keys;
      _me = me;
      _room = room;
      _listening
        ..add(
          room.connected.listen((connected) {
            _connected = connected;
            _set(connected: connected);
            if (connected) {
              // Whatever was said before may not have arrived: say it now.
              _told = null;
              unawaited(_tell());
            }
          }),
        )
        ..add(
          room.ended.listen((ended) {
            _ended = ended;
            if (ended) _set(ended: true);
          }),
        )
        ..add(
          room.entries.listen((entries) async {
            final companions = <Companion>[];
            for (final entry in entries) {
              if (entry.participant == me) continue;
              final message = await keys.open(entry.box, entry.participant);
              final shared = message == null
                  ? null
                  : Shared.fromMessage(message);
              if (shared == null) continue;
              companions.add(
                Companion(
                  participant: entry.participant,
                  heardAt: entry.at.subtract(room.clockOffset),
                  shared: shared,
                ),
              );
            }
            companions.sort((a, b) => b.heardAt.compareTo(a.heardAt));
            if (generation == _generation) {
              _set(heard: true, companions: companions);
            }
          }, onError: (Object _) {}),
        );
      _ticker = Timer.periodic(tick, (_) => unawaited(_tell()));
    } on RelayUnavailable catch (error) {
      if (generation == _generation) {
        status.value = GroupStatus(problem: error.reason);
      }
    }
  }

  /// Tells the group [_mine] if the policy says so; one at a time.
  Future<void> _tell({bool force = false}) async {
    final running = _telling;
    if (running != null) {
      await running;
      if (!force) return;
    }
    final (room, keys, me, mine) = (_room, _keys, _me, _mine);
    if (room == null || keys == null || me == null || mine == null) return;
    if (!_connected || _ended) return;
    final now = _clock();
    if (!force &&
        !SharePolicy.of(mine.mode).due(mine, _told, _toldAt ?? now, now)) {
      return;
    }
    final telling = () async {
      try {
        await room.publish(++_seq, await keys.seal(mine.toMessage(), me));
        _told = mine;
        _toldAt = now;
      } on Object {
        // Tried again on the next tick; nothing is queued.
      }
    }();
    _telling = telling;
    await telling;
    _telling = null;
  }

  /// The journey ended: says so (if the relay is reachable) and, for the
  /// inviter, ends the group for everyone.
  Future<void> finish({required bool endGroup}) async {
    final mine = _mine;
    if (mine != null) {
      _mine = Shared(
        name: mine.name,
        phase: JourneyPhase.ended,
        mode: mine.mode,
        fix: mine.fix,
      );
      await _tell(force: true);
    }
    if (endGroup && _connected) {
      try {
        await _room?.end();
      } on Object {
        // Offline: the group stays until its members leave.
      }
    }
    await stop();
  }

  /// Ends the group for everyone (its inviter), the journey going on.
  Future<void> endGroup() async {
    try {
      await _room?.end();
    } on Object {
      // Offline: the group stays until its members leave.
    }
    await stop();
  }

  /// Leaves the group: this phone's entries go; the group goes on.
  Future<void> leave() async {
    try {
      await _room?.leave();
    } on Object {
      // Offline: the entries stay until the relay forgets them (G7).
    }
    await stop();
  }

  void _set({
    bool? connected,
    bool? heard,
    bool? ended,
    List<Companion>? companions,
  }) {
    final now = status.value ?? const GroupStatus();
    status.value = GroupStatus(
      connected: connected ?? now.connected,
      heard: heard ?? now.heard,
      ended: ended ?? now.ended,
      companions: companions ?? now.companions,
      problem: now.problem,
    );
  }

  /// Stops sharing and listening, and forgets the status.
  Future<void> stop() async {
    _mine = null;
    await _leaveRoom();
  }

  Future<void> _leaveRoom() async {
    _generation++;
    _ticker?.cancel();
    _ticker = null;
    for (final listening in _listening) {
      await listening.cancel();
    }
    _listening.clear();
    await _room?.close();
    _room = null;
    _keys = null;
    _me = null;
    _secret = null;
    _told = null;
    _toldAt = null;
    _connected = false;
    _ended = false;
    status.value = null;
  }
}
