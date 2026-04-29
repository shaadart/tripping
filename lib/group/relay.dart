/// A member's latest entry in a room, as the relay holds it.
class RelayEntry {
  const RelayEntry({
    required this.participant,
    required this.seq,
    required this.at,
    required this.box,
  });

  /// The relay's id for the member who wrote it.
  final String participant;

  /// Counts up with every entry that member writes.
  final int seq;

  /// When the relay received it, on the relay's clock.
  final DateTime at;

  /// The sealed message (see `GroupKeys`).
  final String box;
}

/// Why the relay cannot be used at all, as opposed to being unreachable for
/// a while.
class RelayUnavailable implements Exception {
  const RelayUnavailable(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Where a group's members meet (D-034): Firebase today, replaceable.
abstract interface class Relay {
  /// This install's id at the relay, signing in on first use.
  Future<String> me();

  /// Opens [room]. The inviter [create]s it; others may only join a room
  /// that exists.
  Future<RelayRoom> open(String room, {required bool create});

  /// Takes this install's entries out of [room] without following it, and
  /// removes the room if no one is left (G7).
  Future<void> leaveRoom(String room);
}

abstract interface class RelayRoom {
  /// Whether the relay is reachable now. Says nothing about delivery or
  /// anyone's position.
  Stream<bool> get connected;

  /// The relay's clock minus this phone's.
  Duration get clockOffset;

  /// Every member's latest entry, whenever any changes.
  Stream<List<RelayEntry>> get entries;

  /// Writes this member's latest entry. Never queued: call it only while
  /// [connected].
  Future<void> publish(int seq, String box);

  /// Whether the group has been closed (by an earlier version, whose
  /// inviter could end it).
  Stream<bool> get ended;

  /// Takes this member out of the group: its entries go, the group stays;
  /// the last one out also removes the room.
  Future<void> leave();

  /// Removes [participant]'s entries, silent for over a day (G7).
  Future<void> forget(String participant);

  /// Stops listening; the membership stays.
  Future<void> close();
}
