import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 320 dp phone with the system text at 200%: the hardest fit the app
/// promises to handle (DS-7).
void onSmallPhoneAtDoubleText(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Nothing overflowed or threw, and every target is large and labelled.
Future<void> expectComfortable(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}
