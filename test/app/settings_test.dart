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
}
