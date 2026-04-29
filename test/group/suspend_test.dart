import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/group_sync.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/group/relay.dart';
import 'package:tripping/group/sharing.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

import '../support/fake_relay.dart';

final at = DateTime.utc(2026, 10, 29);
MembershipRow member() => MembershipRow(
  journeyId: 1,
  groupId: 'fictional-group',
  secret: newSecret(),
  role: GroupRole.member,
  joinedAt: at,
);
const mine = Shared(
  name: 'Asha',
  phase: JourneyPhase.recording,
  mode: JourneyMode.road,
);

class ConnectingRelay extends FakeRelay {
  final opening = Completer<RelayRoom>();
  @override
  Future<RelayRoom> open(String room, {required bool create}) => opening.future;
}

class SlowRelay extends FakeRelay {
  final writing = Completer<void>();
  int epoch = 0;
  @override
  Future<void> resume() async {
    epoch++;
    await super.resume();
  }

  @override
  Future<void> suspend() async {
    epoch++;
    await super.suspend();
  }

  @override
  Future<void> publish(int seq, String box) async {
    final started = epoch;
    await writing.future;
    if (started != epoch) throw StateError('write purged');
    await super.publish(seq, box);
  }
}

class FailingSuspendRelay extends FakeRelay {
  bool fail = false;
  @override
  Future<void> suspend() async {
    await super.suspend();
    if (fail) throw const RelayUnavailable('Could not stop sign-in');
  }
}

void main() {
  test(
    'shutdown failure still closes room and cancels every listener',
    () async {
      final relay = FailingSuspendRelay()..reachable = true;
      final sync = GroupSync(relay);
      await sync.follow(member());
      await pumpEventQueue();
      relay.fail = true;
      await expectLater(sync.suspend(), throwsA(isA<RelayUnavailable>()));
      expect(relay.closed, 1);
      expect(relay.connection.hasListener, isFalse);
      expect(relay.changes.hasListener, isFalse);
      expect(relay.endings.hasListener, isFalse);
      relay.fail = false;
      await sync.stop();
    },
  );
  test(
    'pause removes every timer/listener and ignores reconnection for five simulated days',
    () {
      fakeAsync((async) {
        final relay = FakeRelay()..reachable = true;
        final sync = GroupSync(relay, clock: () => at.add(async.elapsed));
        sync.follow(member());
        sync.update(mine);
        async.flushMicrotasks();
        expect(relay.published, hasLength(1));
        expect(relay.changes.hasListener, isTrue);
        sync.suspend();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
        expect(relay.connection.hasListener, isFalse);
        expect(relay.changes.hasListener, isFalse);
        expect(relay.endings.hasListener, isFalse);
        expect(sync.status.value?.suspended, isTrue);
        final sent = relay.published.length;
        relay.reach(false);
        relay.reach(true);
        async.elapse(const Duration(days: 5));
        expect(relay.published, hasLength(sent));
        expect(relay.opened, hasLength(1));
        sync.stop();
        async.flushMicrotasks();
      });
    },
  );

  test('a late room open cannot restart a paused connection', () async {
    final relay = ConnectingRelay()..reachable = true;
    final sync = GroupSync(relay);
    final opening = sync.follow(member());
    await pumpEventQueue();
    await sync.suspend();
    relay.opening.complete(relay);
    await opening;
    expect(relay.closed, 1);
    expect(relay.changes.hasListener, isFalse);
    expect(relay.published, isEmpty);
    expect(sync.status.value?.suspended, isTrue);
    await sync.stop();
  });

  test(
    'pause does not wait for a blocked publication and resume uses a new session',
    () async {
      final relay = SlowRelay()..reachable = true;
      final sync = GroupSync(relay);
      final membership = member();
      await sync.follow(membership);
      sync.update(mine);
      await pumpEventQueue();
      await sync.suspend().timeout(const Duration(seconds: 1));
      expect(sync.status.value?.suspended, isTrue);
      relay.writing.complete();
      await pumpEventQueue();
      expect(relay.published, isEmpty, reason: 'the old write was purged');
      sync.update(mine);
      await sync.follow(membership);
      await pumpEventQueue();
      expect(relay.published, hasLength(1));
      await sync.stop();
    },
  );
}
