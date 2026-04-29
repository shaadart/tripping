import 'dart:async';

import 'package:flutter/foundation.dart';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import 'convoy.dart';
import 'group_keys.dart';
import 'relay.dart';
import 'sharing.dart';

/// Someone else in the group, as last heard.
class Companion {
  const Companion({
    required this.participant,
    required this.heardAt,
    required this.shared,
    this.stillSince,
  });

  final String participant;

  /// When the relay last received from them, on this phone's clock.
  final DateTime heardAt;

  /// What they last said: name, phase, mode and their newest saved fix.
  final Shared shared;

  String get name => shared.name;

  /// Since when they have stood still while recording, once that is longer
  /// than two minutes (G6).
  final DateTime? stillSince;

  /// When their position was taken, on this phone's clock: the relay's
  /// receipt less its age when sent, so neither phone's clock error
  /// matters (G4). Null without a position.
  DateTime? get positionAt {
    final fix = shared.fix;
    if (fix == null) return null;
    final age = shared.fixAge;
    return age == null ? fix.time : heardAt.subtract(age);
  }
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
    this.offlineSince,
    this.refused = false,
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

  /// Since when the relay has been out of reach (this phone's clock).
  final DateTime? offlineSince;

  /// The relay keeps refusing this phone's updates (it may have been
  /// removed, or the group closed).
  final bool refused;
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
  var _refusals = 0;

  /// After this long without a word, a member's entries go (G7).
  static const expireAfter = Duration(hours: 24);
  final _forgotten = <String>{};

  /// Who has stood still where, per companion.
  final _still = <String, Stillness>{};

  /// Each companion's newest genuine entry.
  final _heard = <String, ({int seq, DateTime at, Companion companion})>{};

  /// Boxes larger than this are not even opened (the relay's rules allow
  /// 1,024 characters).
  static const maxBox = 1024;
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
            final since = status.value?.offlineSince;
            _set(
              connected: connected,
              offlineSince: connected ? null : since ?? _clock(),
              clearOffline: connected,
            );
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
            final silentSince = _clock().subtract(expireAfter);
            for (final entry in entries) {
              if (entry.participant == me) continue;
              // Silent for over a day: gone from the group (G7). Its
              // entries are removed for everyone, once.
              if (entry.at.subtract(room.clockOffset).isBefore(silentSince)) {
                if (_forgotten.add(entry.participant)) {
                  unawaited(
                    room.forget(entry.participant).catchError((Object _) {}),
                  );
                }
                continue;
              }
              // Duplicates and anything older than what is shown change
              // nothing (invariant 9).
              final known = _heard[entry.participant];
              if (known != null &&
                  (entry.at.isBefore(known.at) ||
                      (entry.at == known.at && entry.seq <= known.seq))) {
                continue;
              }
              if (entry.box.length > maxBox) continue;
              final message = await keys.open(entry.box, entry.participant);
              final shared = message == null
                  ? null
                  : Shared.fromMessage(message);
              // A damaged entry leaves the last good one in place.
              if (shared == null) continue;
              final heard = Companion(
                participant: entry.participant,
                heardAt: entry.at.subtract(room.clockOffset),
                shared: shared,
              );
              final still = _still.putIfAbsent(
                entry.participant,
                Stillness.new,
              );
              final fix = shared.fix;
              final positionAt = heard.positionAt;
              final stillSince =
                  fix != null &&
                      positionAt != null &&
                      shared.phase == JourneyPhase.recording
                  ? still.update(fix, positionAt)
                  : null;
              _heard[entry.participant] = (
                seq: entry.seq,
                at: entry.at,
                companion: Companion(
                  participant: entry.participant,
                  heardAt: heard.heardAt,
                  shared: shared,
                  stillSince: stillSince,
                ),
              );
            }
            final present = {
              for (final e in entries)
                if (!_forgotten.contains(e.participant)) e.participant,
            };
            _heard.removeWhere(
              (participant, _) => !present.contains(participant),
            );
            final companions = [for (final h in _heard.values) h.companion]
              ..sort((a, b) => b.heardAt.compareTo(a.heardAt));
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
        await room.publish(
          ++_seq,
          await keys.seal(mine.toMessage(at: now), me),
        );
        _told = mine;
        _toldAt = now;
        if (_refusals > 0) {
          _refusals = 0;
          _set(refused: false);
        }
      } on Object {
        // Tried again on the next tick; nothing is queued. Refused again
        // and again while reachable: say so.
        if (_connected && ++_refusals >= 3) _set(refused: true);
      }
    }();
    _telling = telling;
    await telling;
    _telling = null;
  }

  /// The journey ended: says so once, if the relay is reachable, then
  /// shares nothing more. The group goes on without this phone (D-037).
  Future<void> finish() async {
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
    bool? refused,
    List<Companion>? companions,
    DateTime? offlineSince,
    bool clearOffline = false,
  }) {
    final now = status.value ?? const GroupStatus();
    status.value = GroupStatus(
      connected: connected ?? now.connected,
      heard: heard ?? now.heard,
      ended: ended ?? now.ended,
      refused: refused ?? now.refused,
      companions: companions ?? now.companions,
      problem: now.problem,
      offlineSince: clearOffline ? null : offlineSince ?? now.offlineSince,
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
    _refusals = 0;
    _heard.clear();
    _still.clear();
    _forgotten.clear();
    _connected = false;
    _ended = false;
    status.value = null;
  }
}
