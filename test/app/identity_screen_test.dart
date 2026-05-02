import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/identity_marker.dart';
import 'package:tripping/app/identity_screen.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/group/identity.dart';

void main() {
  late Directory dir;
  late Settings settings;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('tripping_identity');
    settings = await Settings.open(File('${dir.path}/settings.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets(
    'one welcome screen saves name, colour and shape across reopening',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: trippingLook(Look.light),
          home: IdentityGate(
            settings: settings,
            child: const Scaffold(body: Text('Journey home')),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Zoya Khan');
      await tester.tap(find.byTooltip('River'));
      await tester.ensureVisible(find.byTooltip('Rounded square'));
      await tester.tap(find.byTooltip('Rounded square'));
      await tester.pumpAndSettle();
      expect(find.text('River · Gate'), findsNothing);
      expect(find.byType(IdentityMarker), findsNWidgets(7));
      await tester.ensureVisible(find.text("Let's go"));
      await tester.runAsync(() async {
        await tester.tap(find.text("Let's go"));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Journey home'), findsOneWidget);
      final again = await tester.runAsync(
        () => Settings.open(File('${dir.path}/settings.json')),
      );
      expect(again!.identityReady, isTrue);
      expect(again.identity.value.description, 'Zoya Khan, River, Gate');
    },
  );

  testWidgets('the action takes your colour and neighbours never share it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingLook(Look.light),
        home: IdentityScreen(settings: settings, welcome: true, onSaved: () {}),
      ),
    );
    for (final colour in IdentityColour.values) {
      await tester.tap(find.byTooltip(colour.label));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(
        button.style!.backgroundColor!.resolve({}),
        Color(colour.argb),
        reason: colour.label,
      );
      final markers = tester
          .widgetList<IdentityMarker>(find.byType(IdentityMarker))
          .map((m) => m.identity)
          .where((i) => i.name == 'Asha' || i.name == 'Tom');
      expect(markers, hasLength(2));
      for (final other in markers) {
        expect(other.colour, isNot(colour));
      }
    }
  });

  testWidgets(
    'small phone with 200% text scrolls to comfortable labelled controls',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: trippingLook(Look.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: IdentityScreen(
              settings: settings,
              welcome: true,
              onSaved: () {},
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.byTooltip('Rounded square'));
      await tester.pumpAndSettle();
      for (final label in [
        ...IdentityColour.values.map((c) => c.label),
        ...MarkerShape.values.map(markerShapeLabel),
      ]) {
        final target = tester.getSize(find.byTooltip(label));
        expect(target.width, greaterThanOrEqualTo(64));
        expect(target.height, greaterThanOrEqualTo(64));
      }
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, "Let's go")).height,
        greaterThanOrEqualTo(48),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    },
  );

  testWidgets('failed save keeps welcome open and the draft recoverable', (
    tester,
  ) async {
    final missing = (await tester.runAsync(
      () => Settings.open(File('${dir.path}/missing/settings.json')),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityGate(
          settings: missing,
          child: const Text('Journey home'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Asha');
    await tester.ensureVisible(find.text("Let's go"));
    await tester.runAsync(() async {
      await tester.tap(find.text("Let's go"));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save your marker'), findsOneWidget);
    expect(missing.identityReady, isFalse);
    expect(find.text('Journey home'), findsNothing);
  });

  testWidgets(
    'marker palette is readable and every silhouette differs in every look',
    (tester) async {
      for (final colour in IdentityColour.values) {
        expect(
          (1.05) / (Color(colour.argb).computeLuminance() + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
      final captures = <MarkerShape, List<int>>{};
      for (final shape in MarkerShape.values) {
        final png = await tester.runAsync(
          () => identityMarkerPng(MapIdentity(name: 'Asha Rao', shape: shape)),
        );
        expect(png, isNotEmpty);
        captures[shape] = png!;
      }
      for (final a in MarkerShape.values) {
        for (final b in MarkerShape.values.where((b) => b != a)) {
          expect(captures[a], isNot(orderedEquals(captures[b]!)));
        }
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: Column(
              children: [
                for (final look in Look.values)
                  Expanded(
                    child: Theme(
                      data: trippingLook(look),
                      child: Builder(
                        builder: (context) => Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (final shape in MarkerShape.values)
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IdentityMarker(
                                      identity: MapIdentity(
                                        name: 'Asha Rao',
                                        shape: shape,
                                      ),
                                      size: 72,
                                    ),
                                    Text(markerShapeLabel(shape)),
                                    IdentityMarker(
                                      identity: MapIdentity(
                                        name: 'Ravi',
                                        shape: shape,
                                        colour: IdentityColour.river,
                                      ),
                                      hollow: true,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (Platform.environment['TRIPPING_CAPTURE_IDENTITY'] case final path?) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(path).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    },
  );
}
