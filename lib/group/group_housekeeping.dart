import '../journey/journey_store.dart';
import 'group_keys.dart';
import 'group_sync.dart';
import 'relay.dart';

/// Takes this phone's entries out of the groups of journeys that ended more
/// than a day ago, removes those rooms if no one is left, and forgets the
/// groups here (G7, D-040); also finishes leaving [pendingRooms]. What fails
/// (offline, say) is tried at the next start. Touches the relay only when there is something to tidy.
Future<int> tidyGroups(
  JourneyStore store,
  Relay relay, {
  required DateTime now,
  bool Function()? shouldContinue,
  Iterable<String> pendingRooms = const [],
  Future<void> Function(String room)? onRoomLeft,
}) async {
  var tidied = 0;
  // Rooms left while offline: this phone's last position goes now.
  for (final room in List.of(pendingRooms)) {
    if (shouldContinue?.call() == false) return tidied;
    try {
      await relay.leaveRoom(room);
      await onRoomLeft?.call(room);
      tidied++;
    } on Object {
      // Next connection.
    }
  }
  final cutoff = now.subtract(GroupSync.expireAfter);
  for (final membership in await store.membershipsEndedBefore(cutoff)) {
    if (shouldContinue?.call() == false) break;
    try {
      final keys = await GroupKeys.derive(membership.secret);
      if (shouldContinue?.call() == false) break;
      await relay.leaveRoom(keys.room);
      await store.deleteMembership(membership.journeyId);
      tidied++;
    } on Object {
      // Next start.
    }
  }
  return tidied;
}
