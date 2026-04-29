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
    this.suspended = false,
  });

  /// The relay is reachable now.
  final bool connected;

  /// Transport deliberately stopped; connectivity does not resume it.
  final bool suspended;

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
    this.onConnected,
  }) : _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final Relay _relay;
  final Duration tick;
  final Future<void> Function()? onConnected;
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
    final generation = ++_generation;
    await _leaveRoom();
    if (generation != _generation) return;
    _secret = membership?.secret;
    if (membership == null) return;
    status.value = const GroupStatus();
    try {
      final keys = await GroupKeys.derive(membership.secret);
      if (generation != _generation) return;
      await _relay.resume();
      if (generation != _generation) return;
      final me = await _relay.me();
      if (generation != _generation) return;
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
            if (generation != _generation) return;
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
              unawaited(onConnected?.call().catchError((Object _) {}));
            }
          }),
        )
        ..add(
          room.ended.listen((ended) {
            if (generation != _generation) return;
            _ended = ended;
            if (ended) _set(ended: true);
          }),
        )
        ..add(
          room.entries.listen((entries) async {
            if (generation != _generation) return;
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
              if (generation != _generation) return;
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
    final generation = _generation;
    final running = _telling;
    if (running != null) {
      await running;
      if (!force) return;
    }
    if (generation != _generation) return;
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
        final box = await keys.seal(mine.toMessage(at: now), me);
        if (generation != _generation) return;
        await room.publish(++_seq, box);
        if (generation != _generation) return;
        _told = mine;
        _toldAt = now;
        if (_refusals > 0) {
          _refusals = 0;
          _set(refused: false);
        }
      } on Object {
        // Tried again on the next tick; nothing is queued. Refused again
        // and again while reachable: say so.
        if (generation == _generation && _connected && ++_refusals >= 3) {
          _set(refused: true);
        }
      }
    }();
    _telling = telling;
    await telling;
    if (identical(_telling, telling)) _telling = null;
  }

  /// The journey ended: says so once, if the relay is reachable, then
  /// shares nothing more. The group goes on without this phone (D-037).
  Future<void> finish() async {
    final mine = _mine;
    if (mine != null) {
      _mine = Shared(
        name: mine.name,
        colour: mine.colour,
        shape: mine.shape,
        phase: JourneyPhase.ended,
        mode: mine.mode,
        fix: mine.fix,
      );
      await _tell(
        force: true,
      ).timeout(const Duration(milliseconds: 350), onTimeout: () {});
    }
    await stop();
  }

  /// Leaves the group: this phone's entries go; the group goes on.
  Future<void> leave() async {
    try {
      await _room?.leave().timeout(
        const Duration(milliseconds: 350),
        onTimeout: () {},
      );
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

  /// Full/sharing pause: keep membership and last-known companion data,
  /// but cancel timers, listeners, queued writes and reconnect activity.
  Future<void> suspend() async {
    ++_generation; // Invalidates connecting/decrypting/publishing work now.
    _mine = null;
    final previous = status.value;
    final stopped = _leaveRoom();
    if (previous != null) {
      status.value = GroupStatus(
        suspended: true,
        heard: previous.heard,
        companions: previous.companions,
        ended: previous.ended,
      );
    }
    await stopped;
  }

  /// Stops sharing and forgets the group shown. Membership stays on disk.
  Future<void> stop() async {
    ++_generation;
    _mine = null;
    await _leaveRoom();
  }

  Future<void> _leaveRoom() async {
    // Retire state before any await; a late callback cannot reconnect or
    // change a newer session. Closing also releases pending join streams.
    final room = _room;
    final subscriptions = List.of(_listening);
    _ticker?.cancel();
    _ticker = null;
    _listening.clear();
    _room = null;
    _keys = null;
    _me = null;
    _secret = null;
    _told = null;
    _toldAt = null;
    _telling = null;
    _refusals = 0;
    _heard.clear();
    _still.clear();
    _forgotten.clear();
    _connected = false;
    _ended = false;
    status.value = null;
    try {
      await _relay.suspend();
    } finally {
      try {
        await room?.close();
      } finally {
        await Future.wait([
          for (final subscription in subscriptions) subscription.cancel(),
        ]);
      }
    }
  }
}
