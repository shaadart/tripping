import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/main.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tripping_settings');
    file = File('${dir.path}/settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('high sun is off until switched on, and is remembered', () async {
    final first = await Settings.open(file);
    expect(first.highSun.value, isFalse);

    await first.setHighSun(true);
    expect((await Settings.open(file)).highSun.value, isTrue);
    expect(File('${file.path}.next').existsSync(), isFalse);
  });

  test('the participant id is made once and kept', () async {
    final first = await Settings.open(file);
    final id = await first.participantId();
    expect(id, hasLength(22));
    expect(await first.participantId(), id);
    expect(await (await Settings.open(file)).participantId(), id);
  });

  test('the name is asked for once, kept as one short line', () async {
    final first = await Settings.open(file);
    expect(first.name.value, isNull);
    await first.setName('  Asha\n Rao ');
    expect(first.name.value, 'Asha Rao');
    final again = await Settings.open(file);
    expect(again.name.value, 'Asha Rao');
    // Other settings survive alongside.
    await again.setHighSun(true);
    expect((await Settings.open(file)).name.value, 'Asha Rao');
  });

  test(
    'sharing-only pause survives reopen without changing other settings',
    () async {
      final settings = await Settings.open(file);
      await Future.wait([
        settings.setName('Ravi'),
        settings.setSharingPaused('fictional-journey', true),
        settings.setHighSun(true),
      ]);
      final reopened = await Settings.open(file);
      expect(reopened.sharingPaused('fictional-journey'), isTrue);
      expect(reopened.name.value, 'Ravi');
      expect(reopened.highSun.value, isTrue);
      await reopened.setSharingPaused('fictional-journey', false);
      expect(
        (await Settings.open(file)).sharingPaused('fictional-journey'),
        isFalse,
      );
    },
  );

  test('an unreadable file means the defaults, not a failed start', () async {
    file.writeAsStringSync('{not json');
    expect((await Settings.open(file)).highSun.value, isFalse);
  });

  testWidgets('the app switches to the high-sun look and back', (tester) async {
    final highSun = ValueNotifier(false);
    late BuildContext inner;
    await tester.pumpWidget(
      TrippingApp(
        highSun: highSun,
        home: Builder(
          builder: (context) {
            inner = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(lookOf(inner).look, Look.light);

    highSun.value = true;
    await tester.pumpAndSettle();
    expect(lookOf(inner).look, Look.highSun);
    expect(lookOf(inner).mapStyle, 'assets/map/sun.json');
  });

  test('rooms still to be cleared after leaving are remembered', () async {
    final first = await Settings.open(file);
    await first.addPendingLeave('room-1');
    final again = await Settings.open(file);
    expect(again.pendingLeaves, {'room-1'});
    await again.removePendingLeave('room-1');
    expect((await Settings.open(file)).pendingLeaves, isEmpty);
  });
}
