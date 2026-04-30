import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/map/map_style.dart';
import 'package:tripping/map/map_symbols.dart';
import 'package:tripping/map/map_key.dart';
import 'package:tripping/map/track_geometry.dart';

import '../app/contrast_test.dart' show contrast, mapFills;
import '../support/fakes.dart';

class _Map implements MapLibreMapController {
  final calls = <Invocation>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return Future<void>.value();
  }
}

void main() {
  test('a live origin never announces a recorded finish', () {
    final ends =
        endsFeatures([
              [],
              [walkFix(0), walkFix(1)],
              [],
              [walkFix(10)],
            ], includeFinish: false)['features']!
            as List;
    expect(ends, hasLength(1));
    expect((ends.single as Map)['properties'], {'end': 'start'});
  });

  for (final look in Look.values) {
    testWidgets(
      '${look.name}: routes stay visible beside recorded ground; direction-only is distinct',
      (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            theme: trippingLook(look),
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        );
        final map = _Map();
        await addRouteLayers(map, context, 'way');
        await addRecordedLayers(map, context, ['history', 'tail']);
        final lines = {
          for (final c in map.calls.where((c) => c.memberName == #addLineLayer))
            c.positionalArguments[1] as String:
                c.positionalArguments[2] as LineLayerProperties,
        };
        expect(
          lines['way-road']!.lineWidth as double,
          greaterThan((lines['history-casing']!.lineWidth as double) + 4),
        );
        expect(lines['history-line']!.lineDasharray, isNull);
        expect(lines['way-straight']!.lineDasharray, isNotEmpty);
        expect(
          lines['way-straight']!.lineWidth as num,
          lessThan(lines['history-line']!.lineWidth as num),
        );
        final ordered = map.calls.map((c) => c.positionalArguments[1]).toList();
        expect(
          ordered.indexOf('tail-casing'),
          lessThan(ordered.indexOf('history-line')),
        );
        expect(
          ordered.indexOf('way-direction'),
          lessThan(ordered.indexOf('history-line')),
        );
        final arrow = map.calls.firstWhere(
          (c) => c.positionalArguments[1] == 'way-direction',
        );
        expect(arrow.namedArguments[#filter], [
          '==',
          ['get', 'kind'],
          'road',
        ]);
        expect(
          (arrow.positionalArguments[2] as SymbolLayerProperties)
              .iconKeepUpright,
          isFalse,
        );
        final v = MapVisuals(context);
        for (final fill in mapFills(v.look.mapStyle).values) {
          expect(contrast(v.route, fill), greaterThanOrEqualTo(3));
          expect(contrast(v.recorded, fill), greaterThanOrEqualTo(3));
        }
        expect(contrast(v.arrow, v.route), greaterThanOrEqualTo(3));
        final images = await tester.runAsync(
          () async => [
            for (final symbol in MapSymbol.values)
              await mapSymbolPng(symbol, v),
          ],
        );
        // The arrow must be completely hidden where recorded ink/casing
        // covers the planned route, rather than peeking out as fragments.
        final arrowHeight = await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(images!.last);
          final image = (await codec.getNextFrame()).image;
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final rows = <int>[];
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              if (pixels.getUint8((y * image.width + x) * 4 + 3) > 0) {
                rows.add(y);
                break;
              }
            }
          }
          image.dispose();
          codec.dispose();
          return (rows.last - rows.first + 1) / 3;
        });
        expect(arrowHeight!, lessThanOrEqualTo(v.trackCasingWidth));
        for (var i = 0; i < images!.length; i++) {
          for (var j = i + 1; j < images.length; j++) {
            expect(images[i], isNot(orderedEquals(images[j])));
          }
        }
      },
    );
  }

  testWidgets('native colours use final tokens during a theme transition', (
    tester,
  ) async {
    late MapVisuals visuals;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.lerp(
          trippingLook(Look.light),
          trippingLook(Look.dark),
          .75,
        ),
        home: Builder(
          builder: (context) {
            visuals = MapVisuals(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(visuals.ground, Palette.night);
    expect(visuals.route, Palette.riverNight);
  });

  testWidgets(
    'map key is labelled, optional and scrollable at 200% on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: trippingLook(Look.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: MapKeyButton()),
        ),
      );
      expect(find.text('Recorded ground'), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.tap(find.byTooltip('Map symbols'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('GPS uncertainty'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
