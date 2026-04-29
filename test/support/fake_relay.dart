import 'dart:async';

import 'package:tripping/group/relay.dart';

/// A relay in memory: one room, entries as written, reachability switched
/// by the test.
class FakeRelay implements Relay, RelayRoom {
  final connection = StreamController<bool>.broadcast();
  final changes = StreamController<List<RelayEntry>>.broadcast();
  final published = <(int, String)>[];
  final opened = <(String, bool)>[];
  var reachable = false;
  var closed = 0;
  RelayUnavailable? unavailable;

  @override
  Future<String> me() async => 'me';

  @override
  Future<RelayRoom> open(String room, {required bool create}) async {
    if (unavailable case final error?) throw error;
    opened.add((room, create));
    return this;
  }

  @override
  Stream<bool> get connected async* {
    yield reachable;
    yield* connection.stream;
  }

  @override
  Duration get clockOffset => const Duration(seconds: 2);

  @override
  Stream<List<RelayEntry>> get entries => changes.stream;

  @override
  Future<void> publish(int seq, String box) async {
    if (!reachable) throw StateError('would have been queued');
    published.add((seq, box));
  }

  @override
  Future<void> close() async => closed++;

  void reach(bool on) {
    reachable = on;
    connection.add(on);
  }
}
