import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// A group's relay room and the key its messages are sealed with, both
/// derived from the invitation's secret (D-036). The relay sees the room
/// name, which does not reveal the key, and only sealed boxes.
class GroupKeys {
  GroupKeys._(this.room, this._key);

  static final _cipher = AesGcm.with256bits();
  static final _salt = utf8.encode('tripping-group-v1');

  /// Derives the room and key from [secret] (22 base64url characters).
  static Future<GroupKeys> derive(String secret) async {
    final ikm = SecretKey(base64Url.decode('$secret=='));
    Future<List<int>> part(String info, int length) async =>
        (await Hkdf(hmac: Hmac.sha256(), outputLength: length).deriveKey(
          secretKey: ikm,
          nonce: _salt,
          info: utf8.encode(info),
        )).extractBytes();
    final room = base64Url.encode(await part('room', 16)).replaceAll('=', '');
    return GroupKeys._(room, SecretKey(await part('key', 32)));
  }

  /// The room's name at the relay: 128 bits, unguessable, not the key.
  final String room;
  final SecretKey _key;

  /// [message] as an opaque box for [sender]'s slot: nonce, ciphertext and
  /// tag, in base64url. Bound to [sender], so a box copied into another
  /// member's slot does not open.
  Future<String> seal(Map<String, Object?> message, String sender) async {
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(message)),
      secretKey: _key,
      aad: utf8.encode(sender),
    );
    return base64Url.encode(box.concatenation());
  }

  /// The message in [box] from [sender]'s slot, or null when it is not
  /// genuine: another key, another slot, or altered on the way.
  Future<Map<String, Object?>?> open(String box, String sender) async {
    try {
      final bytes = base64Url.decode(box);
      final sealed = SecretBox.fromConcatenation(
        bytes,
        nonceLength: _cipher.nonceLength,
        macLength: _cipher.macAlgorithm.macLength,
      );
      final clear = await _cipher.decrypt(
        sealed,
        secretKey: _key,
        aad: utf8.encode(sender),
      );
      final message = jsonDecode(utf8.decode(clear));
      return message is Map<String, Object?> ? message : null;
    } on Object {
      return null;
    }
  }
}
