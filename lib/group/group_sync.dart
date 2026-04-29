import 'dart:async';

import 'package:flutter/foundation.dart';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import 'group_keys.dart';
import 'relay.dart';

/// Someone else in the group, as last heard.
class Companion {
  const Companion({
    required this.participant,
    required this.name,
    required this.heardAt,
  });

  final String participant;
  final String name;

  /// When the relay last received from them, on this phone's clock.
  final DateTime heardAt;
}

/// What the screen may say about the group: reachable or not, and who was
/// heard when. Never more.
class GroupStatus {
  const GroupStatus({
    this.connected = false,
    this.heard = false,
    this.companions = const [],
    this.problem,
  });

  /// The relay is reachable now.
  final bool connected;

  /// The room's entries have been read at least once.
  final bool heard;
  final List<Companion> companions;

  /// Why group sharing cannot work at all here.
  final String? problem;
}

/// Keeps this phone present in its journey's group (G2): joins the room,
/// says "here" with the user's name every [every] while the relay is
/// reachable, and once on reconnecting, never queued; and turns the room's
/// entries into companions.
class GroupSync {
  GroupSync(this._relay, {this.every = const Duration(seconds: 30)});

  final Relay _relay;
  final Duration every;

  /// Null while the journey shown is in no group.
  final status = ValueNotifier<GroupStatus?>(null);

  String? _secret;
  RelayRoom? _room;
  final _listening = <StreamSubscription<Object?>>[];
  Timer? _ticker;
  var _connected = false;
  var _seq = 0;
  int _generation = 0;

  /// Follows [membership] as [name]: joins its room, or leaves the current
  /// one when it is null or another.
  Future<void> follow(MembershipRow? membership, String name) async {
    if (membership?.secret == _secret) return;
    await stop();
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
      _room = room;
      Future<void> say() async {
        if (!_connected || generation != _generation) return;
        try {
          await room.publish(++_seq, await keys.seal({'name': name}, me));
        } on Object {
          // The next beat tries again; nothing is queued.
        }
      }

      _listening
        ..add(
          room.connected.listen((connected) {
            _connected = connected;
            _set(connected: connected);
            if (connected) unawaited(say());
          }),
        )
        ..add(
          room.entries.listen((entries) async {
            final companions = <Companion>[];
            for (final entry in entries) {
              if (entry.participant == me) continue;
              final message = await keys.open(entry.box, entry.participant);
              final name = message?['name'];
              if (name is! String) continue;
              companions.add(
                Companion(
                  participant: entry.participant,
                  name: name,
                  heardAt: entry.at.subtract(room.clockOffset),
                ),
              );
            }
            companions.sort((a, b) => b.heardAt.compareTo(a.heardAt));
            if (generation == _generation) {
              _set(heard: true, companions: companions);
            }
          }, onError: (Object _) {}),
        );
      _ticker = Timer.periodic(every, (_) => unawaited(say()));
    } on RelayUnavailable catch (error) {
      if (generation == _generation) {
        status.value = GroupStatus(problem: error.reason);
      }
    }
  }

  void _set({bool? connected, bool? heard, List<Companion>? companions}) {
    final now = status.value ?? const GroupStatus();
    status.value = GroupStatus(
      connected: connected ?? now.connected,
      heard: heard ?? now.heard,
      companions: companions ?? now.companions,
      problem: now.problem,
    );
  }

  /// Leaves the room (the group itself goes on) and forgets the status.
  Future<void> stop() async {
    _generation++;
    _ticker?.cancel();
    _ticker = null;
    for (final listening in _listening) {
      await listening.cancel();
    }
    _listening.clear();
    await _room?.close();
    _room = null;
    _secret = null;
    _connected = false;
    status.value = null;
  }
}
