import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/group_keys.dart';
import 'package:tripping/group/group_sync.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/group/relay.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

import '../support/fake_relay.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);

MembershipRow membership(String secret, {GroupRole role = GroupRole.member}) =>
    MembershipRow(
      journeyId: 1,
      groupId: 'g',
      secret: secret,
      role: role,
      hostName: 'Asha',
      joinedAt: t0,
    );

void main() {
  final secret = newSecret();
  late FakeRelay relay;
  late GroupSync sync;

  setUp(() {
    relay = FakeRelay();
    sync = GroupSync(relay, every: const Duration(seconds: 30));
  });

  test('joins the room derived from the secret; the inviter creates it', () {
    fakeAsync((async) {
      sync.follow(membership(secret, role: GroupRole.creator), 'Ravi');
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      expect(relay.opened.single.$2, isTrue);
      expect(relay.opened.single.$1, hasLength(22));
      expect(sync.status.value?.connected, isFalse);
    });
  });

  test('says "here" on connecting and every 30 s, never while offline', () {
    fakeAsync((async) {
      sync.follow(membership(secret), 'Ravi');
      async.flushMicrotasks();
      expect(relay.published, isEmpty, reason: 'offline: nothing queued');
      async.elapse(const Duration(seconds: 60));
      expect(relay.published, isEmpty);

      relay.reach(true);
      async.flushMicrotasks();
      expect(relay.published, hasLength(1), reason: 'once on connecting');
      expect(sync.status.value?.connected, isTrue);
      async.elapse(const Duration(seconds: 61));
      expect(relay.published.map((p) => p.$1), [1, 2, 3]);

      relay.reach(false);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 90));
      expect(relay.published, hasLength(3));
      expect(sync.status.value?.connected, isFalse);
    });
  });

  test('what it says is sealed: the name is not in the box', () async {
    relay.reachable = true;
    await sync.follow(membership(secret), 'Ravi');
    await pumpEventQueue();
    final box = relay.published.single.$2;
    expect(box, isNot(contains('Ravi')));
    final keys = await GroupKeys.derive(secret);
    expect(await keys.open(box, 'me'), {'name': 'Ravi'});
  });

  test('companions: others only, genuine only, newest first', () async {
    final keys = await GroupKeys.derive(secret);
    await sync.follow(membership(secret), 'Ravi');
    relay.changes.add([
      RelayEntry(
        participant: 'me',
        seq: 1,
        at: t0,
        box: await keys.seal({'name': 'Ravi'}, 'me'),
      ),
      RelayEntry(
        participant: 'a',
        seq: 4,
        at: t0.add(const Duration(seconds: 10)),
        box: await keys.seal({'name': 'Asha'}, 'a'),
      ),
      RelayEntry(
        participant: 'b',
        seq: 2,
        at: t0.add(const Duration(seconds: 50)),
        box: await keys.seal({'name': 'Meera'}, 'b'),
      ),
      // Asha's box copied into another slot: refused.
      RelayEntry(
        participant: 'c',
        seq: 1,
        at: t0,
        box: await keys.seal({'name': 'Asha'}, 'a'),
      ),
    ]);
    await pumpEventQueue();
    final status = sync.status.value!;
    expect(status.heard, isTrue);
    expect([for (final c in status.companions) c.name], ['Meera', 'Asha']);
    // Relay time minus the relay's 2 s lead.
    expect(status.companions.last.heardAt, t0.add(const Duration(seconds: 8)));
  });

  test('another group, or none, leaves the room', () async {
    await sync.follow(membership(secret), 'Ravi');
    await sync.follow(membership(secret), 'Ravi');
    expect(relay.opened, hasLength(1), reason: 'same group: stays');
    await sync.follow(membership(newSecret()), 'Ravi');
    expect((relay.opened.length, relay.closed), (2, 1));
    await sync.follow(null, 'Ravi');
    expect(relay.closed, 2);
    expect(sync.status.value, isNull);
  });

  test('a relay that cannot work says why', () async {
    relay.unavailable = const RelayUnavailable('Group sharing is unavailable');
    await sync.follow(membership(secret), 'Ravi');
    expect(sync.status.value?.problem, 'Group sharing is unavailable');
  });
}
