import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/group_auth.dart';
import 'package:tripping/group/relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tripping/group_auth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'pause waits for identity preservation before parking transport auth',
    () async {
      final preserving = Completer<String>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'restore' ? preserving.future : null;
      });
      final restoring = GroupAuth.change('restore');
      final parking = GroupAuth.change('park');
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['restore']);
      preserving.complete('fictional-uid');
      expect(await restoring, 'fictional-uid');
      await parking;
      expect(calls, ['restore', 'park']);
    },
  );

  test(
    'failed auth operation is unavailable and does not poison next pause',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'restore') throw PlatformException(code: 'offline');
        return null;
      });
      await expectLater(
        GroupAuth.change('restore'),
        throwsA(isA<RelayUnavailable>()),
      );
      await GroupAuth.change('park');
    },
  );
}
