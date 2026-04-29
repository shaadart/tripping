import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/invite.dart';

const groupId = '0192f5a4-3b1c-7d2e-8f00-123456789abc';

void main() {
  test('a secret is 128 random bits in 22 characters', () {
    final secret = newSecret();
    expect(secret, hasLength(22));
    expect(Invite.isSecret(secret), isTrue);
    expect(newSecret(), isNot(secret));
  });

  test('a link round-trips, name and all', () {
    final invite = Invite.create(groupId, 'Asha & Ravi', random: Random(1));
    expect(invite.link, startsWith('tripping://invite/join?g=$groupId&k='));
    expect(Invite.find(invite.link), invite);
  });

  test('found inside a message, as pasted from a chat', () {
    final invite = Invite.create(groupId, 'Asha');
    final message = 'Join my Tripping group:\n${invite.link}\nSee you!';
    expect(Invite.find(message), invite);
  });

  test('damaged or foreign links are refused', () {
    final good = Invite.create(groupId, 'Asha', random: Random(2));
    String swap(String from, String to) => good.link.replaceFirst(from, to);
    expect(Invite.find('no invite here'), isNull);
    expect(Invite.find(swap(good.secret, good.secret.substring(1))), isNull);
    expect(Invite.find(swap(groupId, 'not-a-uuid')), isNull);
    expect(Invite.find(swap('n=Asha', 'n=')), isNull);
    expect(Invite.find(swap('tripping://', 'https://')), isNull);
    expect(
      Invite.fromUri(Uri.parse('tripping://other/join?g=$groupId')),
      isNull,
    );
  });

  test('names are one line of at most 40 characters', () {
    expect(Invite.cleanName('  Asha\n  Rao  '), 'Asha Rao');
    expect(Invite.cleanName('x' * 60), hasLength(40));
    final long = Invite.create(groupId, 'y' * 40);
    expect(Invite.find(long.link)!.hostName, hasLength(40));
  });
}
