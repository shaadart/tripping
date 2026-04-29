import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late JourneyStore store;
  late int journey;

  setUp(() async {
    store = JourneyStore(NativeDatabase.memory());
    journey = (await store.startJourney(JourneyMode.road, at: t0)).id;
  });
  tearDown(() => store.close());

  Future<void> join(int id, {String group = 'g-1'}) => store.saveMembership(
    id,
    groupId: group,
    secret: 'k' * 22,
    role: GroupRole.member,
    hostName: 'Asha',
    at: t0,
  );

  test('a membership is kept with its journey, and watched', () async {
    final seen = <MembershipRow?>[];
    final watching = store.watchMembership(journey).listen(seen.add);
    expect(await store.membershipOf(journey), isNull);
    await join(journey);
    final row = (await store.membershipOf(journey))!;
    expect(
      (row.groupId, row.role, row.hostName, row.joinedAt),
      ('g-1', GroupRole.member, 'Asha', t0),
    );
    await pumpEventQueue();
    expect(seen.last?.groupId, 'g-1');
    await watching.cancel();
  });

  test('a journey is in one group: a second is refused, not swapped', () async {
    await join(journey);
    await expectLater(join(journey, group: 'g-2'), throwsStateError);
    expect((await store.membershipOf(journey))!.groupId, 'g-1');
  });

  test('deleting the journey deletes its membership', () async {
    await join(journey);
    await store.end(journey, at: t0.add(const Duration(minutes: 1)));
    await store.deleteJourney(journey);
    expect(await store.membershipOf(journey), isNull);
  });
}
