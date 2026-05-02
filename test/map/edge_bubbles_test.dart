import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/identity_marker.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/group/group_sync.dart';
import 'package:tripping/group/identity.dart';
import 'package:tripping/group/sharing.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/map/edge_bubbles.dart';
import 'package:tripping/map/edge_geometry.dart';

import '../support/large_text.dart';

final t0 = DateTime.utc(2026, 11, 2, 8);
const metersPerDegree = 111195.08;

Companion companion(
  String name, {
  double north = 1200,
  Duration age = const Duration(seconds: 10),
  JourneyPhase phase = JourneyPhase.recording,
}) => Companion(
  participant: name.toLowerCase(),
  heardAt: t0,
  shared: Shared(
    name: name,
    phase: phase,
    mode: JourneyMode.expedition,
    colour: IdentityColour.moss,
    shape: MarkerShape.reed,
    fix: Fix(
      time: t0.subtract(age),
      latitude: 12.97 + north / metersPerDegree,
      longitude: 77.59,
    ),
    fixAge: age,
  ),
);

final here = Fix(time: t0, latitude: 12.97, longitude: 77.59);

void main() {
  Future<void> show(
    WidgetTester tester,
    List<Companion> companions, {
    VoidCallback? onShow,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingLook(Look.light),
        home: Scaffold(
          body: Center(
            child: EdgeBubbleView(
              bubble: EdgeBubble(
                [for (final c in companions) c.participant],
                Offset.zero,
                0,
              ),
              companions: companions,
              now: t0,
              here: here,
              onShow: onShow ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('one companion: their marker, how far, and a way to show them', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var shown = 0;
    await show(tester, [companion('Asha')], onShow: () => shown++);
    expect(find.byType(IdentityMarker), findsOneWidget);
    expect(find.text('1.2 km N'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Asha, 1.2 km N, off the map. Show them'),
      findsOneWidget,
    );
    await tester.tap(find.byType(EdgeBubbleView));
    expect(shown, 1);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('several in one direction: how many, and who', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, [companion('Asha'), companion('Meera', north: 1300)]);
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(IdentityMarker), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp(r'^2 companions .*: Asha, Meera\.')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a stale or paused companion is drawn hollow, as on the map', (
    tester,
  ) async {
    await show(tester, [companion('Asha', age: const Duration(hours: 1))]);
    expect(
      tester.widget<IdentityMarker>(find.byType(IdentityMarker)).hollow,
      isTrue,
    );
    await show(tester, [companion('Tom', phase: JourneyPhase.paused)]);
    expect(
      tester.widget<IdentityMarker>(find.byType(IdentityMarker)).hollow,
      isTrue,
    );
    await show(tester, [companion('Noor')]);
    expect(
      tester.widget<IdentityMarker>(find.byType(IdentityMarker)).hollow,
      isFalse,
    );
  });

  testWidgets('fits at 200% text on a small phone', (tester) async {
    onSmallPhoneAtDoubleText(tester);
    final semantics = tester.ensureSemantics();
    await show(tester, [companion('Asha')]);
    await expectComfortable(tester);
    // No room for a label on a short map: the distance is still spoken.
    expect(find.text('1.2 km N'), findsNothing);
    expect(
      find.bySemanticsLabel('Asha, 1.2 km N, off the map. Show them'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
