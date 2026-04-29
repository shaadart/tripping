// Checks the live database rules (firebase/database.rules.json) against
// G2's acceptance: who may create, join, read and write a group room.
//
//   dart run tool/relay_check.dart
//
// Uses three new anonymous users and a fresh random room; writes only test
// entries there.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'src/firebase_rest.dart';

Future<void> main() async {
  final fb = FirebaseRest.fromSettings();
  final random = Random.secure();
  final room = base64Url
      .encode([for (var i = 0; i < 16; i++) random.nextInt(256)])
      .replaceAll('=', '');
  final (a, aToken) = await fb.signUp(); // the inviter
  final (b, bToken) = await fb.signUp(); // a companion
  final (c, cToken) = await fb.signUp(); // someone without the room's name
  var failures = 0;

  Future<void> expect(
    String what,
    String method,
    String path,
    String? token,
    int wanted, [
    Object? body,
  ]) async {
    final (status, _) = await fb.call(method, fb.at(path, token), body);
    final ok = status == wanted;
    if (!ok) failures++;
    stdout.writeln('${ok ? 'PASS' : 'FAIL'} $what: $status (want $wanted)');
  }

  final presence = {'seq': 1, 'at': FirebaseRest.now, 'box': 'x' * 100};
  final r = 'rooms/$room';

  await expect(
    'join a room that does not exist',
    'PUT',
    '$r/members/$b',
    bToken,
    401,
    {'joined': FirebaseRest.now},
  );
  await expect('create the room', 'PUT', '$r/meta', aToken, 200, {
    'created': FirebaseRest.now,
  });
  await expect('create it again', 'PUT', '$r/meta', bToken, 401, {
    'created': FirebaseRest.now,
  });
  await expect('read it before joining', 'GET', '$r/presence', bToken, 401);
  await expect('list rooms', 'GET', 'rooms', aToken, 401);
  await expect('read without signing in', 'GET', '$r/presence', null, 401);
  await expect('inviter joins', 'PUT', '$r/members/$a', aToken, 200, {
    'joined': FirebaseRest.now,
  });
  await expect('companion joins', 'PUT', '$r/members/$b', bToken, 200, {
    'joined': FirebaseRest.now,
  });
  await expect('join as someone else', 'PUT', '$r/members/$c', bToken, 401, {
    'joined': FirebaseRest.now,
  });
  await expect(
    'presence before joining',
    'PUT',
    '$r/presence/$c',
    cToken,
    401,
    presence,
  );
  await expect('own presence', 'PUT', '$r/presence/$b', bToken, 200, presence);
  await expect(
    'again within 2 s',
    'PUT',
    '$r/presence/$b',
    bToken,
    401,
    presence,
  );
  await expect(
    'write into another member',
    'PUT',
    '$r/presence/$a',
    bToken,
    401,
    presence,
  );
  await Future<void>.delayed(const Duration(milliseconds: 2200));
  await expect(
    'a box over 1,024 characters',
    'PUT',
    '$r/presence/$b',
    bToken,
    401,
    {...presence, 'box': 'x' * 1100},
  );
  await expect(
    'a time set by the phone',
    'PUT',
    '$r/presence/$b',
    bToken,
    401,
    {...presence, 'at': 123},
  );
  await expect('an extra field', 'PUT', '$r/presence/$b', bToken, 401, {
    ...presence,
    'where': 'here',
  });
  await expect('members read the room', 'GET', '$r/presence', bToken, 200);
  await expect(
    'inviter writes',
    'PUT',
    '$r/presence/$a',
    aToken,
    200,
    presence,
  );
  await expect(
    'inviter leaves (presence)',
    'DELETE',
    '$r/presence/$a',
    aToken,
    200,
  );
  await expect(
    'inviter leaves (membership)',
    'DELETE',
    '$r/members/$a',
    aToken,
    200,
  );
  await expect(
    'the inviter, gone, cannot read',
    'GET',
    '$r/presence',
    aToken,
    401,
  );
  await Future<void>.delayed(const Duration(milliseconds: 2200));
  await expect(
    'the group goes on without the inviter',
    'PUT',
    '$r/presence/$b',
    bToken,
    200,
    {...presence, 'seq': 2},
  );
  await expect('and is still readable', 'GET', '$r/presence', bToken, 200);
  await expect(
    'a newcomer with the name joins',
    'PUT',
    '$r/members/$c',
    cToken,
    200,
    {'joined': FirebaseRest.now},
  );

  stdout.writeln(failures == 0 ? 'ALL PASS' : '$failures FAILED');
  fb.client.close(force: true);
  exit(failures == 0 ? 0 : 1);
}
