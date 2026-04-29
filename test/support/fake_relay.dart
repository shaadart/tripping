import 'dart:async';

import 'package:tripping/group/relay.dart';

/// A relay in memory: one room, entries as written, reachability switched
/// by the test.
class FakeRelay implements Relay, RelayRoom {
  final connection = StreamController<bool>.broadcast();
  final changes = StreamController<List<RelayEntry>>.broadcast();
  final published = <(int, String)>[];
  final endings = StreamController<bool>.broadcast();
  var left = 0;
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

  /// The relay's clock minus this phone's.
  Duration offset = const Duration(seconds: 2);

  @override
  Duration get clockOffset => offset;

  @override
  Stream<List<RelayEntry>> get entries => changes.stream;

  /// Makes the relay refuse writes, as its rules would.
  var refusing = false;

  @override
  Future<void> publish(int seq, String box) async {
    if (!reachable) throw StateError('would have been queued');
    if (refusing) throw StateError('permission denied');
    published.add((seq, box));
  }

  @override
  Stream<bool> get ended => endings.stream;

  @override
  Future<void> leave() async => left++;

  @override
  Future<void> close() async => closed++;

  void reach(bool on) {
    reachable = on;
    connection.add(on);
  }
}
