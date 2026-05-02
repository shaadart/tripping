import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/group_housekeeping.dart';
import 'package:tripping/group/group_keys.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

import '../support/fake_relay.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late JourneyStore store;
  late FakeRelay relay;
  final secret = newSecret();

  setUp(() {
    store = JourneyStore(NativeDatabase.memory());
    relay = FakeRelay();
  });
  tearDown(() => store.close());

  Future<int> endedJourneyInGroup({required DateTime endedAt}) async {
    final id = (await store.startJourney(
      JourneyMode.road,
      at: endedAt.subtract(const Duration(hours: 1)),
    )).id;
    await store.saveMembership(
      id,
      groupId: 'g',
      secret: secret,
      role: GroupRole.member,
      at: endedAt,
    );
    await store.end(id, at: endedAt);
    return id;
  }

  test('a day after the journey ended, its part leaves the group', () async {
    final old = await endedJourneyInGroup(endedAt: t0);
    final now = t0.add(const Duration(hours: 25));
    expect(await tidyGroups(store, relay, now: now), 1);
    expect(relay.roomsLeft, [(await GroupKeys.derive(secret)).room]);
    expect(await store.membershipOf(old), isNull);
  });

  test('within the day, nothing is touched', () async {
    await endedJourneyInGroup(endedAt: t0);
    expect(
      await tidyGroups(store, relay, now: t0.add(const Duration(hours: 23))),
      0,
    );
    expect(relay.roomsLeft, isEmpty);
  });

  test('offline: kept, and tried again next time', () async {
    final old = await endedJourneyInGroup(endedAt: t0);
    relay.failLeavingRooms = true;
    final now = t0.add(const Duration(hours: 25));
    expect(await tidyGroups(store, relay, now: now), 0);
    expect(await store.membershipOf(old), isNotNull);
    relay.failLeavingRooms = false;
    expect(await tidyGroups(store, relay, now: now), 1);
  });

  test('no groups: the relay is never touched', () async {
    expect(await tidyGroups(store, relay, now: t0), 0);
    expect(relay.opened, isEmpty);
    expect(relay.roomsLeft, isEmpty);
  });

  test('a room left offline is cleared at the next connection', () async {
    final cleared = <String>[];
    relay.failLeavingRooms = true;
    expect(
      await tidyGroups(
        store,
        relay,
        now: t0,
        pendingRooms: ['room-1'],
        onRoomLeft: (room) async => cleared.add(room),
      ),
      0,
    );
    expect(cleared, isEmpty, reason: 'still offline: kept for next time');
    relay.failLeavingRooms = false;
    expect(
      await tidyGroups(
        store,
        relay,
        now: t0,
        pendingRooms: ['room-1'],
        onRoomLeft: (room) async => cleared.add(room),
      ),
      1,
    );
    expect(relay.roomsLeft, ['room-1']);
    expect(cleared, ['room-1']);
  });
}
