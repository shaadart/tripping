import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/settings.dart';
import 'package:tripping/group/identity.dart';
import 'package:tripping/group/invite.dart';
import 'package:tripping/group/sharing.dart';
import 'package:tripping/journey/journey.dart';

void main() {
  test('initials preserve graphemes and empty names have a usable default', () {
    expect(const MapIdentity().initials, 'T');
    expect(const MapIdentity(name: '  Asha\n Rao ').initials, 'AR');
    expect(const MapIdentity(name: '👩🏽‍🚀 Noor').initials, '👩🏽‍🚀N');
    expect(
      utf8.encode(MapIdentity.cleanName('👩🏽‍🚀' * 40)).length,
      lessThanOrEqualTo(160),
    );
    expect(MapIdentity.cleanName('é' * 50), 'é' * 40);
  });
  test(
    'new invites carry identity; old and future unknown options fall back',
    () {
      final invite = Invite.create(
        '0192f5a4-3b1c-7d2e-8f00-123456789abc',
        'Asha',
        colour: IdentityColour.moss,
        shape: MarkerShape.rosette,
      );
      expect(Invite.find(invite.link), invite);
      final unknown = Invite.fromUri(
        Uri.parse(invite.link).replace(
          queryParameters: {
            ...Uri.parse(invite.link).queryParameters,
            'c': 'future-colour',
            'h': 'future-shape',
          },
        ),
      )!;
      expect(unknown.identity.description, 'Asha, Clay, Tablet');
    },
  );
  test('sealed payload identity round trips and stays bounded for Unicode', () {
    final shared = Shared(
      name: MapIdentity.cleanName('👩🏽‍🚀' * 40),
      phase: JourneyPhase.recording,
      mode: JourneyMode.expedition,
      colour: IdentityColour.river,
      shape: MarkerShape.gate,
    );
    final message = shared.toMessage();
    final decoded = Shared.fromMessage(message)!;
    expect(decoded.identity.description, shared.identity.description);
    expect(utf8.encode(jsonEncode(message)).length, lessThan(350));
    expect(
      Shared.fromMessage({
        'n': 'Ravi',
        's': 'r',
        'm': 'e',
      })!.identity.description,
      'Ravi, Clay, Tablet',
    );
    final now = DateTime.utc(2026, 10, 29);
    const paused = Shared(
      name: 'Ravi',
      phase: JourneyPhase.paused,
      mode: JourneyMode.expedition,
    );
    const edited = Shared(
      name: 'Ravi',
      phase: JourneyPhase.paused,
      mode: JourneyMode.expedition,
      colour: IdentityColour.moss,
    );
    expect(
      SharePolicy.expedition.due(
        edited,
        paused,
        now,
        now.add(const Duration(days: 1)),
      ),
      isFalse,
    );
  });
  test(
    'identity and sharing preference save concurrently without losing either',
    () async {
      final dir = Directory.systemTemp.createTempSync('identity-persist');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/settings.json');
      final settings = await Settings.open(file);
      expect(settings.identityReady, isFalse);
      await Future.wait([
        settings.setIdentity(
          const MapIdentity(
            name: 'Ravi',
            colour: IdentityColour.plum,
            shape: MarkerShape.reed,
          ),
        ),
        settings.setHighSun(true),
        settings.setSharingPaused('fictional', true),
      ]);
      final again = await Settings.open(file);
      expect(again.identity.value.description, 'Ravi, Plum, Reed');
      expect(again.identityReady, isTrue);
      expect(again.highSun.value, isTrue);
      expect(again.sharingPaused('fictional'), isTrue);
    },
  );
  test(
    'legacy named installs retain their name and receive sensible defaults',
    () async {
      final dir = Directory.systemTemp.createTempSync('identity-legacy');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/settings.json')
        ..writeAsStringSync(
          '{"name":"Asha","highSun":true,"identityShape":"unknown"}',
        );
      final settings = await Settings.open(file);
      expect(settings.identity.value.description, 'Asha, Clay, Tablet');
      expect(settings.identityReady, isTrue);
      expect(settings.highSun.value, isTrue);
    },
  );
}
