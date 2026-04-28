import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/main.dart';

void main() {
  testWidgets('the app shows its home screen', (tester) async {
    await tester.pumpWidget(const TrippingApp(home: Text('home')));

    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a storage failure at startup is explained', (tester) async {
    await tester.pumpWidget(
      const TrippingApp(home: StartupFailure(error: 'disk unavailable')),
    );

    expect(find.text('Tripping can’t open its storage'), findsOneWidget);
    expect(find.textContaining('Nothing was recorded or changed'), findsOne);
  });
}
