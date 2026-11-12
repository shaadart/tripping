import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/brand_mark.dart';
import 'package:tripping/app/record_chrome.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/recording/recorder.dart';

void main() {
  for (final look in Look.values) {
    testWidgets('brand mark paints cleanly in ${look.name} look', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: trippingLook(look),
          home: const Scaffold(body: Center(child: BrandMark(size: 64))),
        ),
      );
      expect(find.byType(BrandMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('idle header and welcome display the brand mark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingLook(Look.light),
        home: const Scaffold(
          body: Column(
            children: [
              Header(state: Idle()),
              Welcome(),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(BrandMark), findsNWidgets(2));
    expect(find.text('Tripping'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
  });

  testWidgets('brandMarkPng renders a valid PNG image', (tester) async {
    final bytes = await tester.runAsync(() => brandMarkPng(dimension: 128));
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(100));
    expect(bytes.sublist(0, 8), const [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
