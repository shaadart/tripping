import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/group_screens.dart';
import 'package:tripping/app/record_chrome.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/app/waypoint_sheet.dart';
import 'package:tripping/group/identity.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

import '../support/large_text.dart';

/// DS-7: every screen redrawn in DS-3..6 fits a 320 dp phone at 200% text,
/// in each look, without overflow and with comfortable targets. Screens with
/// their own fakes are swept in their own test files.
void main() {
  Widget app(Look look, Widget home) =>
      MaterialApp(theme: trippingLook(look), home: home);

  for (final look in Look.values) {
    group('${look.name} look at 200% on 320 dp', () {
      final invite = Invite.create(
        'g-1',
        'Asha Rao',
        colour: IdentityColour.moss,
        shape: MarkerShape.reed,
      );

      testWidgets('invite', (tester) async {
        onSmallPhoneAtDoubleText(tester);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(app(look, InviteScreen(invite: invite)));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('Joining is saved'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await expectComfortable(tester);
        semantics.dispose();
      });

      testWidgets('join, before and after an invite', (tester) async {
        onSmallPhoneAtDoubleText(tester);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          app(look, const JoinScreen(place: JoinPlace.startJourney)),
        );
        await tester.pumpAndSettle();
        await expectComfortable(tester);
        // A fresh screen, not the first one handed an invite.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          app(look, JoinScreen(place: JoinPlace.startJourney, invite: invite)),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Join and start an expedition'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await expectComfortable(tester);
        semantics.dispose();
      });

      testWidgets('waypoint sheet', (tester) async {
        onSmallPhoneAtDoubleText(tester);
        final semantics = tester.ensureSemantics();
        final store = JourneyStore(NativeDatabase.memory());
        addTearDown(store.close);
        final at = DateTime.utc(2026, 11, 2, 8);
        final waypoint = await tester.runAsync(() async {
          final journey = await store.startJourney(
            JourneyMode.expedition,
            at: at,
          );
          return store.addWaypoint(
            journey.id,
            kind: WaypointKind.marked,
            at: at,
            latitude: 12.9763,
            longitude: 77.5929,
            accuracy: 6,
          );
        });
        await tester.pumpWidget(
          app(
            look,
            Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showWaypointSheet(
                    context,
                    store: store,
                    waypoint: waypoint!,
                    warning: 'GPS was approximate when this was marked.',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save'));
        await expectComfortable(tester);
        semantics.dispose();
      });

      testWidgets('journey cards stack and stay whole', (tester) async {
        onSmallPhoneAtDoubleText(tester);
        await tester.pumpWidget(
          app(
            look,
            Scaffold(
              body: ListView(
                children: [
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
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Side by side would crush the names: at 200% they stack.
        expect(
          tester.getTopLeft(find.text('Expedition')).dy,
          greaterThan(tester.getTopLeft(find.text('Road journey')).dy),
        );
      });
    });
  }
}
