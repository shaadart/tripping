import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/group_keys.dart';
import 'package:tripping/group/group_sync.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/group/relay.dart';
import 'package:tripping/group/sharing.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

import '../support/fake_relay.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);
const metersPerDegree = 111195.08;

MembershipRow membership(String secret, {GroupRole role = GroupRole.member}) =>
    MembershipRow(
      journeyId: 1,
      groupId: 'g',
      secret: secret,
      role: role,
      hostName: 'Asha',
      joinedAt: t0,
    );

Fix fixAt(int second, double north) => Fix(
  time: t0.add(Duration(seconds: second)),
  latitude: 11.4 + north / metersPerDegree,
  longitude: 76.7,
  accuracy: 5,
);

Shared me(Fix? fix, {JourneyPhase phase = JourneyPhase.recording}) =>
    Shared(name: 'Ravi', phase: phase, mode: JourneyMode.road, fix: fix);

void main() {
  final secret = newSecret();
  late FakeRelay relay;

  /// Runs [body] on a fake clock that GroupSync reads too.
  void onFakeClock(void Function(FakeAsync async, GroupSync sync) body) {
    fakeAsync((async) {
      final sync = GroupSync(relay, clock: () => t0.add(async.elapsed));
      body(async, sync);
      sync.stop();
      async.flushMicrotasks();
    });
  }

  setUp(() => relay = FakeRelay());

  test('joins the room derived from the secret; the inviter creates it', () {
    onFakeClock((async, sync) {
      sync.follow(membership(secret, role: GroupRole.creator));
      async.flushMicrotasks();
      expect(relay.opened.single.$2, isTrue);
      expect(relay.opened.single.$1, hasLength(22));
    });
  });

  test('road: tells at once, then every 10 s or 100 m; never offline', () {
    onFakeClock((async, sync) {
      sync.follow(membership(secret));
      async.flushMicrotasks();
      sync.update(me(fixAt(0, 0)));
      async.elapse(const Duration(seconds: 30));
      expect(relay.published, isEmpty, reason: 'offline: nothing queued');

      relay.reach(true);
      async.flushMicrotasks();
      expect(relay.published, hasLength(1), reason: 'at once on connecting');

      // 50 m in 3 s: not yet.
      async.elapse(const Duration(seconds: 3));
      sync.update(me(fixAt(33, 50)));
      async.flushMicrotasks();
      expect(relay.published, hasLength(1));
      // 105 m by 5 s: now.
      async.elapse(const Duration(seconds: 2));
      sync.update(me(fixAt(35, 105)));
      async.flushMicrotasks();
      expect(relay.published, hasLength(2));
      // Standing still: again after 10 s.
      async.elapse(const Duration(seconds: 9));
      expect(relay.published, hasLength(2));
      async.elapse(const Duration(seconds: 2));
      expect(relay.published, hasLength(3));
      // A pause goes at once.
      async.elapse(const Duration(seconds: 3));
      sync.update(me(fixAt(49, 105), phase: JourneyPhase.paused));
      async.flushMicrotasks();
      expect(relay.published, hasLength(4));

      relay.reach(false);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 2));
      expect(relay.published, hasLength(4), reason: 'offline again');
      relay.reach(true);
      async.flushMicrotasks();
      expect(relay.published, hasLength(5), reason: 'once on reconnecting');
    });
  });

  test('what it tells is sealed: no name, no coordinates in clear', () async {
    relay.reachable = true;
    final sync = GroupSync(relay);
    await sync.follow(membership(secret));
    sync.update(me(fixAt(0, 0)));
    await pumpEventQueue();
    final box = relay.published.single.$2;
    expect(box, isNot(contains('Ravi')));
    expect(box, isNot(contains('11.4')));
    final keys = await GroupKeys.derive(secret);
    final told = Shared.fromMessage((await keys.open(box, 'me'))!)!;
    expect((told.name, told.fix!.latitude), ('Ravi', 11.4));
    await sync.stop();
  });

  test('companions: others only, genuine only, with what they said', () async {
    final keys = await GroupKeys.derive(secret);
    final sync = GroupSync(relay);
    await sync.follow(membership(secret));
    final asha = Shared(
      name: 'Asha',
      phase: JourneyPhase.paused,
      mode: JourneyMode.expedition,
      fix: fixAt(0, 300),
    ).toMessage();
    relay.changes.add([
      RelayEntry(
        participant: 'me',
        seq: 1,
        at: t0,
        box: await keys.seal(me(null).toMessage(), 'me'),
      ),
      RelayEntry(
        participant: 'a',
        seq: 4,
        at: t0.add(const Duration(seconds: 10)),
        box: await keys.seal(asha, 'a'),
      ),
      // Asha's box copied into another slot: refused.
      RelayEntry(
        participant: 'c',
        seq: 1,
        at: t0,
        box: await keys.seal(asha, 'a'),
      ),
    ]);
    await pumpEventQueue();
    final companion = sync.status.value!.companions.single;
    expect(companion.name, 'Asha');
    expect(companion.shared.phase, JourneyPhase.paused);
    expect(
      companion.shared.fix!.latitude,
      closeTo(fixAt(0, 300).latitude, 1e-5),
    );
    expect(companion.heardAt, t0.add(const Duration(seconds: 8)));
    await sync.stop();
  });

  test('ending a journey says so; the inviter ends the group', () async {
    relay.reachable = true;
    final sync = GroupSync(relay);
    await sync.follow(membership(secret, role: GroupRole.creator));
    sync.update(me(fixAt(0, 0)));
    await pumpEventQueue();
    await sync.finish(endGroup: true);
    final keys = await GroupKeys.derive(secret);
    final last = Shared.fromMessage(
      (await keys.open(relay.published.last.$2, 'me'))!,
    )!;
    expect(last.phase, JourneyPhase.ended);
    expect(relay.endedByMe, 1);
    expect(sync.status.value, isNull);
  });

  test('a member ending only says so; leaving takes its entries', () async {
    relay.reachable = true;
    final sync = GroupSync(relay);
    await sync.follow(membership(secret));
    sync.update(me(fixAt(0, 0)));
    await pumpEventQueue();
    await sync.finish(endGroup: false);
    expect(relay.endedByMe, 0);
    await sync.follow(membership(secret));
    await sync.leave();
    expect(relay.left, 1);
  });

  test('when the inviter ends the group, nothing more is told', () {
    onFakeClock((async, sync) {
      relay.reachable = true;
      sync.follow(membership(secret));
      async.flushMicrotasks();
      sync.update(me(fixAt(0, 0)));
      async.flushMicrotasks();
      expect(relay.published, hasLength(1));
      relay.endings.add(true);
      async.flushMicrotasks();
      expect(sync.status.value!.ended, isTrue);
      async.elapse(const Duration(minutes: 1));
      expect(relay.published, hasLength(1));
    });
  });

  test('a relay that cannot work says why', () async {
    relay.unavailable = const RelayUnavailable('Group sharing is unavailable');
    final sync = GroupSync(relay);
    await sync.follow(membership(secret));
    expect(sync.status.value?.problem, 'Group sharing is unavailable');
  });
}
