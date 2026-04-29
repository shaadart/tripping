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

  Future<void> close();
}
