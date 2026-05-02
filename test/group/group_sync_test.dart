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
    final sync = GroupSync(relay, clock: () => t0);
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

  test('ending a journey says so once; the group goes on, even for the '
      'inviter', () async {
    relay.reachable = true;
    final sync = GroupSync(relay);
    await sync.follow(membership(secret, role: GroupRole.creator));
    sync.update(me(fixAt(0, 0)));
    await pumpEventQueue();
    await sync.finish();
    final keys = await GroupKeys.derive(secret);
    final last = Shared.fromMessage(
      (await keys.open(relay.published.last.$2, 'me'))!,
    )!;
    expect(last.phase, JourneyPhase.ended);
    expect(relay.left, 0, reason: 'its entry stays, saying it ended');
    expect(sync.status.value, isNull);
  });

  test('leaving takes this phone\'s entries; the group goes on', () async {
    relay.reachable = true;
    final sync = GroupSync(relay);
    await sync.follow(membership(secret, role: GroupRole.creator));
    await sync.leave();
    expect(relay.left, 1);
  });

  test('paused: says so once, then nothing until resumed', () {
    onFakeClock((async, sync) {
      relay.reachable = true;
      sync.follow(membership(secret));
      async.flushMicrotasks();
      sync.update(me(fixAt(0, 0)));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      sync.update(me(fixAt(0, 0), phase: JourneyPhase.paused));
      async.flushMicrotasks();
      expect(relay.published, hasLength(2));
      async.elapse(const Duration(minutes: 10));
      expect(relay.published, hasLength(2), reason: 'silent while paused');
      sync.update(me(fixAt(0, 0)));
      async.flushMicrotasks();
      expect(relay.published, hasLength(3), reason: 'resumed: at once');
    });
  });

  test(
    'a closed group (an earlier version could close one) gets nothing more',
    () {
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
    },
  );

  test('a relay that cannot work says why', () async {
    relay.unavailable = const RelayUnavailable('Group sharing is unavailable');
    final sync = GroupSync(relay);
    await sync.follow(membership(secret));
    expect(sync.status.value?.problem, 'Group sharing is unavailable');
  });

  group('failure injection (G5)', () {
    late GroupKeys keys;
    late GroupSync sync;
    Shared asha(int ageSeconds) => Shared(
      name: 'Asha',
      phase: JourneyPhase.recording,
      mode: JourneyMode.road,
      fix: fixAt(-ageSeconds, 100),
    );
    Future<RelayEntry> entry(
      int seq,
      DateTime at, {
      String participant = 'a',
      Shared? said,
      String? box,
    }) async => RelayEntry(
      participant: participant,
      seq: seq,
      at: at,
      box:
          box ??
          await keys.seal((said ?? asha(0)).toMessage(at: at), participant),
    );
    setUp(() async {
      keys = await GroupKeys.derive(secret);
      sync = GroupSync(relay, clock: () => t0);
      await sync.follow(membership(secret));
    });
    tearDown(() => sync.stop());

    test('a duplicate or an older entry changes nothing', () async {
      final newer = await entry(5, t0, said: asha(10));
      relay.changes.add([newer]);
      await pumpEventQueue();
      final shown = sync.status.value!.companions.single;
      relay.changes.add([newer]);
      relay.changes.add([
        await entry(
          4,
          t0.subtract(const Duration(seconds: 30)),
          said: asha(40),
        ),
      ]);
      await pumpEventQueue();
      expect(
        identical(sync.status.value!.companions.single, shown),
        isTrue,
        reason: 'the newer entry stays',
      );
    });

    test('a damaged or oversized entry leaves the last good one', () async {
      relay.changes.add([await entry(5, t0)]);
      await pumpEventQueue();
      for (final box in ['not a box', 'x' * 2000]) {
        relay.changes.add([
          await entry(6, t0.add(const Duration(seconds: 10)), box: box),
        ]);
        await pumpEventQueue();
        expect(
          sync.status.value!.companions.single.heardAt,
          t0.subtract(relay.offset),
        );
      }
    });

    test('a 10-minute delay shows a 10-minute-old position', () async {
      relay.changes.add([
        await entry(
          9,
          t0.subtract(const Duration(minutes: 10)).add(relay.offset),
        ),
      ]);
      await pumpEventQueue();
      final companion = sync.status.value!.companions.single;
      expect(t0.difference(companion.positionAt!), const Duration(minutes: 10));
    });

    test('someone who left is no longer listed', () async {
      relay.changes.add([
        await entry(5, t0),
        await entry(5, t0, participant: 'b'),
      ]);
      await pumpEventQueue();
      expect(sync.status.value!.companions, hasLength(2));
      relay.changes.add([await entry(5, t0)]);
      await pumpEventQueue();
      expect(sync.status.value!.companions, hasLength(1));
    });
  });

  test('a companion standing still for over 2 minutes is "stopped"', () async {
    final keys = await GroupKeys.derive(secret);
    final sync = GroupSync(relay, clock: () => t0);
    await sync.follow(membership(secret));
    for (final minute in [0, 1, 2, 3]) {
      final at = t0.add(Duration(minutes: minute));
      final said = Shared(
        name: 'Asha',
        phase: JourneyPhase.recording,
        mode: JourneyMode.road,
        fix: Fix(time: at, latitude: 11.4, longitude: 76.7 + minute * 1e-5),
      );
      relay.changes.add([
        RelayEntry(
          participant: 'a',
          seq: minute + 1,
          at: at,
          box: await keys.seal(said.toMessage(at: at), 'a'),
        ),
      ]);
      await pumpEventQueue();
    }
    expect(
      sync.status.value!.companions.single.stillSince,
      t0.subtract(relay.offset),
    );
    await sync.stop();
  });

  test('a member silent for over a day is forgotten, once', () async {
    final keys = await GroupKeys.derive(secret);
    final sync = GroupSync(relay, clock: () => t0);
    await sync.follow(membership(secret));
    final said = Shared(
      name: 'Asha',
      phase: JourneyPhase.ended,
      mode: JourneyMode.road,
      fix: fixAt(0, 0),
    );
    final old = RelayEntry(
      participant: 'a',
      seq: 9,
      at: t0.subtract(const Duration(hours: 25)),
      box: await keys.seal(said.toMessage(), 'a'),
    );
    relay.changes.add([old]);
    await pumpEventQueue();
    relay.changes.add([old]);
    await pumpEventQueue();
    expect(relay.forgotten, ['a']);
    expect(sync.status.value!.companions, isEmpty);
    await sync.stop();
  });

  test('refused again and again while reachable: says so', () {
    onFakeClock((async, sync) {
      relay
        ..reachable = true
        ..refusing = true;
      sync.follow(membership(secret));
      async.flushMicrotasks();
      sync.update(me(fixAt(0, 0)));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      expect(sync.status.value!.refused, isTrue);
      relay.refusing = false;
      async.elapse(const Duration(seconds: 3));
      expect(sync.status.value!.refused, isFalse);
    });
  });

  test('offline: since when, cleared on reconnecting', () {
    onFakeClock((async, sync) {
      relay.reachable = true;
      sync.follow(membership(secret));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      relay.reach(false);
      async.flushMicrotasks();
      expect(
        sync.status.value!.offlineSince,
        t0.add(const Duration(minutes: 1)),
      );
      async.elapse(const Duration(minutes: 1));
      relay.reach(true);
      async.flushMicrotasks();
      expect(sync.status.value!.offlineSince, isNull);
    });
  });

  test('ages are right with both clocks 5 minutes off (G4)', () async {
    // This phone's clock runs 5 min slow (the relay is 5 min ahead of it);
    // the sender's runs 5 min fast. True time: t0.
    relay.offset = const Duration(minutes: 5);
    final mine = t0.subtract(const Duration(minutes: 5));
    final sync = GroupSync(relay, clock: () => mine);
    await sync.follow(membership(secret));
    final keys = await GroupKeys.derive(secret);
    final senderNow = t0.add(const Duration(minutes: 5));
    final said = Shared(
      name: 'Asha',
      phase: JourneyPhase.recording,
      mode: JourneyMode.road,
      // A fix 20 s old by the sender's own (fast) clock.
      fix: Fix(
        time: senderNow.subtract(const Duration(seconds: 20)),
        latitude: 11.4,
        longitude: 76.7,
      ),
    );
    relay.changes.add([
      RelayEntry(
        participant: 'a',
        seq: 1,
        at: t0, // the relay's clock is right
        box: await keys.seal(said.toMessage(at: senderNow), 'a'),
      ),
    ]);
    await pumpEventQueue();
    final companion = sync.status.value!.companions.single;
    // Read 3 s later on this phone's (slow) clock: 23 s old, as it truly is.
    final readAt = mine.add(const Duration(seconds: 3));
    expect(
      readAt.difference(companion.positionAt!),
      const Duration(seconds: 23),
    );
    // The fix's own time would have said it was from the future.
    expect(readAt.difference(said.fix!.time).isNegative, isTrue);
    await sync.stop();
  });

  group('trustworthy sharing (Iteration 7)', () {
    late GroupKeys keys;
    late GroupSync sync;
    var now = t0;

    Shared asha({Fix? fix, JourneyPhase phase = JourneyPhase.recording}) =>
        Shared(
          name: 'Asha',
          phase: phase,
          mode: JourneyMode.road,
          fix: fix ?? fixAt(0, 100),
        );

    /// A sealed entry as a session-aware sender writes it: [sentAt] on the
    /// sender's clock, [relayAt] on the relay's.
    Future<RelayEntry> said(
      Shared shared, {
      required String session,
      required int counter,
      required DateTime sentAt,
      required DateTime relayAt,
      int seq = 1,
      Map<String, Object?>? receipts,
      bool legacy = false,
    }) async => RelayEntry(
      participant: 'a',
      seq: seq,
      at: relayAt,
      box: await keys.seal({
        ...shared.toMessage(at: sentAt),
        if (!legacy) 'q': [session, counter],
        if (!legacy) 't': sentAt.millisecondsSinceEpoch ~/ 1000,
        'r': ?receipts,
      }, 'a'),
    );

    Future<void> deliver(List<RelayEntry> entries) async {
      relay.changes.add(entries);
      await pumpEventQueue();
    }

    double shownNorth() =>
        (sync.status.value!.companions.single.shared.fix!.latitude - 11.4) *
        metersPerDegree;

    setUp(() async {
      now = t0;
      keys = await GroupKeys.derive(secret);
      sync = GroupSync(relay, clock: () => now);
      await sync.follow(membership(secret));
    });
    tearDown(() => sync.stop());

    test('a replayed older box with a newer relay time is refused', () async {
      final first = await said(
        asha(fix: fixAt(0, 100)),
        session: 's1',
        counter: 1,
        sentAt: t0,
        relayAt: t0,
      );
      await deliver([
        await said(
          asha(fix: fixAt(10, 300)),
          session: 's1',
          counter: 2,
          sentAt: t0.add(const Duration(seconds: 10)),
          relayAt: t0.add(const Duration(seconds: 10)),
          seq: 2,
        ),
      ]);
      // The relay (or anyone able to write the slot) puts the first box
      // back, stamped later.
      await deliver([
        RelayEntry(
          participant: 'a',
          seq: 3,
          at: t0.add(const Duration(minutes: 5)),
          box: first.box,
        ),
      ]);
      expect(shownNorth(), closeTo(300, 1));
    });

    test('a duplicate counter in the same session changes nothing', () async {
      await deliver([
        await said(
          asha(fix: fixAt(0, 100)),
          session: 's1',
          counter: 4,
          sentAt: t0,
          relayAt: t0,
        ),
      ]);
      await deliver([
        await said(
          asha(fix: fixAt(5, 900)),
          session: 's1',
          counter: 4,
          sentAt: t0.add(const Duration(seconds: 5)),
          relayAt: t0.add(const Duration(seconds: 5)),
          seq: 2,
        ),
      ]);
      expect(shownNorth(), closeTo(100, 1));
    });

    test('a restarted sender (new session, counter from 1) is heard', () async {
      await deliver([
        await said(
          asha(fix: fixAt(0, 100)),
          session: 's1',
          counter: 40,
          sentAt: t0,
          relayAt: t0,
        ),
      ]);
      await deliver([
        await said(
          // Resumed after a restart: the same last fix, now paused.
          asha(fix: fixAt(0, 100), phase: JourneyPhase.paused),
          session: 's2',
          counter: 1,
          sentAt: t0.add(const Duration(minutes: 3)),
          relayAt: t0.add(const Duration(minutes: 3)),
          seq: 1,
        ),
      ]);
      expect(
        sync.status.value!.companions.single.shared.phase,
        JourneyPhase.paused,
      );
    });

    test('an old session replayed after a newer one is refused', () async {
      final old = await said(
        asha(fix: fixAt(0, 100)),
        session: 's1',
        counter: 9,
        sentAt: t0,
        relayAt: t0,
      );
      await deliver([
        await said(
          asha(fix: fixAt(60, 500)),
          session: 's2',
          counter: 1,
          sentAt: t0.add(const Duration(minutes: 1)),
          relayAt: t0.add(const Duration(minutes: 1)),
        ),
      ]);
      await deliver([
        RelayEntry(
          participant: 'a',
          seq: 2,
          at: t0.add(const Duration(minutes: 2)),
          box: old.box,
        ),
      ]);
      expect(shownNorth(), closeTo(500, 1));
    });

    test('once a sender uses sessions, a box without one is refused', () async {
      await deliver([
        await said(
          asha(fix: fixAt(0, 100)),
          session: 's1',
          counter: 1,
          sentAt: t0,
          relayAt: t0,
        ),
      ]);
      await deliver([
        await said(
          asha(fix: fixAt(30, 700)),
          session: '',
          counter: 0,
          sentAt: t0.add(const Duration(seconds: 30)),
          relayAt: t0.add(const Duration(seconds: 30)),
          seq: 2,
          legacy: true,
        ),
      ]);
      expect(shownNorth(), closeTo(100, 1));
    });

    test('snapshots arriving together leave the newest, whatever the order '
        'they finish', () async {
      final entries = [
        for (var c = 1; c <= 5; c++)
          await said(
            asha(fix: fixAt(c, c * 100.0)),
            session: 's1',
            counter: c,
            sentAt: t0.add(Duration(seconds: c)),
            relayAt: t0.add(Duration(seconds: c)),
            seq: c,
          ),
      ];
      // Newest first, then older ones: none may win over counter 5.
      for (final entry in [entries[4], ...entries.take(4)]) {
        relay.changes.add([entry]);
      }
      await pumpEventQueue();
      expect(shownNorth(), closeTo(500, 1));
    });

    test('the age is right when the sender\'s wall clock and GNSS disagree '
        'by an hour', () async {
      // GNSS says the fix is from t0; the sender's wall clock runs an hour
      // fast. The fix reached the sender 20 s before it was sent.
      final senderWall = t0.add(const Duration(hours: 1));
      final shared = Shared(
        name: 'Asha',
        phase: JourneyPhase.recording,
        mode: JourneyMode.road,
        fix: fixAt(0, 100),
        fixArrivedAt: senderWall.subtract(const Duration(seconds: 20)),
      );
      expect(shared.toMessage(at: senderWall)['o'], 20);
      // Without the arrival time the age would have said an hour.
      expect(
        Shared(
          name: 'Asha',
          phase: JourneyPhase.recording,
          mode: JourneyMode.road,
          fix: fixAt(0, 100),
        ).toMessage(at: senderWall)['o'],
        3600,
      );
    });

    test('says when the relay accepted this phone\'s position', () async {
      relay.reach(true);
      await pumpEventQueue();
      now = t0.add(const Duration(seconds: 7));
      sync.update(me(fixAt(7, 0)));
      await pumpEventQueue();
      expect(relay.published, hasLength(1));
      expect(sync.status.value!.sentAt, now);
    });

    test('a companion\'s receipt says which of this phone\'s positions they '
        'have', () async {
      relay.reach(true);
      await pumpEventQueue();
      now = t0.add(const Duration(seconds: 7));
      sync.update(me(fixAt(7, 0)));
      await pumpEventQueue();
      final mine = (await keys.open(relay.published.single.$2, 'me'))!;
      final q = mine['q']! as List<Object?>;
      final (session, counter) = (q[0]! as String, q[1]! as int);
      await deliver([
        await said(
          asha(),
          session: 's1',
          counter: 1,
          sentAt: t0.add(const Duration(seconds: 9)),
          relayAt: t0.add(const Duration(seconds: 9)),
          receipts: {
            'me': [session.substring(0, 4), counter],
          },
        ),
      ]);
      expect(
        sync.status.value!.companions.single.hasMineFrom,
        t0.add(const Duration(seconds: 7)),
      );
    });

    test(
      'a receipt from an earlier run of this phone is not believed',
      () async {
        relay.reach(true);
        await pumpEventQueue();
        sync.update(me(fixAt(0, 0)));
        await pumpEventQueue();
        await deliver([
          await said(
            asha(),
            session: 's1',
            counter: 1,
            sentAt: t0.add(const Duration(seconds: 9)),
            relayAt: t0.add(const Duration(seconds: 9)),
            receipts: {
              'me': ['zzzz', 1],
            },
          ),
        ]);
        expect(sync.status.value!.companions.single.hasMineFrom, isNull);
      },
    );
  });

  test(
    'leaving offline names the room still to be cleared; online, none',
    () async {
      final sync = GroupSync(relay);
      await sync.follow(membership(secret));
      relay.failLeaving = true;
      final room = await sync.leave();
      expect(room, (await GroupKeys.derive(secret)).room);
      expect(relay.left, 0);

      await sync.follow(membership(secret));
      relay.failLeaving = false;
      expect(await sync.leave(), isNull);
      expect(relay.left, 1);
    },
  );
}
