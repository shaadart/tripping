import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/identity_screen.dart';
import 'package:tripping/app/record_chrome.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/map/map_key.dart';

/// DS-7: reference images of the design system's key surfaces, so a change
/// in shape, spacing or colour shows up as a failed comparison. Text renders
/// in the test font (boxes); the layout, colours and drawings are real.
/// Regenerate on purpose with `flutter test --update-goldens test/goldens`.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('tripping_golden'));
  tearDown(() => dir.deleteSync(recursive: true));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final look in [Look.light, Look.dark]) {
    testWidgets('identity welcome, ${look.name}', (tester) async {
      phone(tester);
      final settings = (await tester.runAsync(
        () => Settings.open(File('${dir.path}/settings.json')),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: trippingLook(look),
          home: IdentityScreen(settings: settings, welcome: true),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(IdentityScreen),
        matchesGoldenFile('identity_${look.name}.png'),
      );
    });

    testWidgets('where-to cards, ${look.name}', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: trippingLook(look),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Welcome(),
                  const SizedBox(height: 12),
                  ActionPair(
                    ModeCard(
                      label: 'Road journey',
                      icon: Icons.directions_car_outlined,
                      art: ModeArt.road,
                      onPressed: () {},
                    ),
                    ModeCard(
                      label: 'Expedition',
                      icon: Icons.hiking,
                      art: ModeArt.expedition,
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('where_to_${look.name}.png'),
      );
    });

    testWidgets('map guide, ${look.name}', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: trippingLook(look),
          home: const Scaffold(body: Center(child: MapKeyButton())),
        ),
      );
      await tester.tap(find.byTooltip('Map symbols'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('map_guide_${look.name}.png'),
      );
    });
  }
}
