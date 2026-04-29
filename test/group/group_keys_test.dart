import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/group/group_keys.dart';
import 'package:tripping/group/invite.dart';

void main() {
  final secret = newSecret();

  test('everyone with the secret derives the same room', () async {
    final a = await GroupKeys.derive(secret);
    final b = await GroupKeys.derive(secret);
    expect(a.room, b.room);
    expect(a.room, hasLength(22));
    expect(a.room, isNot(contains(secret)));
    expect((await GroupKeys.derive(newSecret())).room, isNot(a.room));
  });

  test('a sealed message opens with the same secret and slot', () async {
    final keys = await GroupKeys.derive(secret);
    final box = await keys.seal({'name': 'Asha'}, 'uid-a');
    expect(box, isNot(contains('Asha')));
    final again = await GroupKeys.derive(secret);
    expect(await again.open(box, 'uid-a'), {'name': 'Asha'});
  });

  test('a box does not open in another slot, group or altered', () async {
    final keys = await GroupKeys.derive(secret);
    final box = await keys.seal({'name': 'Asha'}, 'uid-a');
    expect(await keys.open(box, 'uid-b'), isNull, reason: 'copied slot');
    final other = await GroupKeys.derive(newSecret());
    expect(await other.open(box, 'uid-a'), isNull, reason: 'other group');
    final flipped = box.replaceRange(30, 31, box[30] == 'A' ? 'B' : 'A');
    expect(await keys.open(flipped, 'uid-a'), isNull, reason: 'altered');
    expect(await keys.open('not base64 !!', 'uid-a'), isNull);
  });

  test('every box is different, even for the same message', () async {
    final keys = await GroupKeys.derive(secret);
    final one = await keys.seal({'name': 'Asha'}, 'uid-a');
    final two = await keys.seal({'name': 'Asha'}, 'uid-a');
    expect(one, isNot(two));
  });
}
