import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/components.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/app/tokens.dart';

Widget host(Widget child, {Look look = Look.light, double textScale = 1}) =>
    MaterialApp(
      theme: trippingLook(look),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  for (final look in Look.values) {
    group('${look.name} look', () {
      testWidgets('map chrome floats on raised ground with a hairline', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            const MapChrome(child: SizedBox(width: 48, height: 48)),
            look: look,
          ),
        );
        final scheme = trippingLook(look).colorScheme;
        final material = tester.widget<Material>(
          find.descendant(
            of: find.byType(MapChrome),
            matching: find.byType(Material),
          ),
        );
        expect(material.color, scheme.surfaceContainerHighest);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, Corner.mediumRadius);
        expect(shape.side.color, scheme.outlineVariant);
        expect(material.clipBehavior, Clip.antiAlias);
      });

      testWidgets('sheet surface rounds only the top', (tester) async {
        await tester.pumpWidget(
          host(const SheetSurface(child: SizedBox(height: 40)), look: look),
        );
        final material = tester.widget<Material>(
          find.descendant(
            of: find.byType(SheetSurface),
            matching: find.byType(Material),
          ),
        );
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, Corner.sheetRadius);
        expect(
          material.color,
          trippingLook(look).colorScheme.surfaceContainerHighest,
        );
      });

      testWidgets('a note says what is wrong in ink and offers one action', (
        tester,
      ) async {
        var pressed = 0;
        await tester.pumpWidget(
          host(
            StatusNote(
              'Location is off.',
              actionLabel: 'Turn on location',
              onAction: () => pressed++,
            ),
            look: look,
          ),
        );
        final scheme = trippingLook(look).colorScheme;
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.icon, Icons.warning_amber_rounded);
        expect(
          icon.color,
          trippingLook(look).extension<TrippingLook>()!.warning,
        );
        final text = tester.widget<Text>(find.text('Location is off.'));
        expect(text.style?.color ?? scheme.onSurface, scheme.onSurface);
        expect(
          tester
              .getSize(find.widgetWithText(OutlinedButton, 'Turn on location'))
              .height,
          greaterThanOrEqualTo(Touch.min),
        );
        await tester.tap(find.text('Turn on location'));
        expect(pressed, 1);
      });
    });
  }

  testWidgets('an error note uses the error colour and icon', (tester) async {
    await tester.pumpWidget(
      host(const StatusNote('Cannot save.', tone: NoteTone.error)),
    );
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.error_outline_rounded);
    expect(icon.color, trippingLook(Look.light).colorScheme.error);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('a note wraps at 200% text without overflowing', (tester) async {
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: StatusNote(
              'Recording stopped at 14:05. The phone closed Tripping, so '
              'nothing after that was recorded.',
              actionLabel: 'Battery settings',
              onAction: () {},
            ),
          ),
        ),
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Battery settings'), findsOneWidget);
  });

  testWidgets('text buttons are ink, so ember stays for the main action', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(TextButton(onPressed: () {}, child: const Text('Past journeys'))),
    );
    final scheme = trippingLook(Look.light).colorScheme;
    final style = tester.widget<TextButton>(find.byType(TextButton)).style;
    final theme = Theme.of(tester.element(find.byType(TextButton)));
    expect(style, isNull);
    expect(
      theme.textButtonTheme.style!.foregroundColor!.resolve({}),
      scheme.onSurface,
    );
  });
}
