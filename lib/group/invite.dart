import 'dart:convert';
import 'dart:math';

/// An invitation to a group (G1): which group, the secret that lets its
/// holder join, and who invited.
///
/// The secret is a capability: anyone holding the link may join, so it is
/// shown only as a QR code or a link the user chooses to share, and never
/// logged.
class Invite {
  const Invite({
    required this.groupId,
    required this.secret,
    required this.hostName,
  });

  /// A new group for the journey [groupId], with a fresh 128-bit secret.
  factory Invite.create(String groupId, String hostName, {Random? random}) =>
      Invite(groupId: groupId, secret: newSecret(random), hostName: hostName);

  /// The inviting journey's uuid.
  final String groupId;

  /// 128 random bits, as 22 characters of unpadded base64url.
  final String secret;

  /// How the inviter named themselves.
  final String hostName;

  static const scheme = 'tripping';
  static const host = 'invite';
  static const path = '/join';

  /// Names are cut to this many characters.
  static const nameLength = 40;

  /// `tripping://invite/join?g=…&k=…&n=…`: opens Tripping when tapped or
  /// scanned, and survives being pasted inside a message.
  String get link => Uri(
    scheme: scheme,
    host: host,
    path: path,
    queryParameters: {'g': groupId, 'k': secret, 'n': hostName},
  ).toString();

  static final _found = RegExp(r'tripping://invite/join\?\S+');
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// The invite in [text]: a link alone, or a message containing one. Null
  /// when there is none, or it is damaged (a wrong-length secret, say).
  static Invite? find(String text) {
    final match = _found.firstMatch(text);
    if (match == null) return null;
    final Uri uri;
    try {
      uri = Uri.parse(match.group(0)!);
    } on FormatException {
      return null;
    }
    return fromUri(uri);
  }

  /// The invite a link carries, or null.
  static Invite? fromUri(Uri uri) {
    if (uri.scheme != scheme || uri.host != host || uri.path != path) {
      return null;
    }
    final groupId = uri.queryParameters['g'] ?? '';
    final secret = uri.queryParameters['k'] ?? '';
    final name = cleanName(uri.queryParameters['n'] ?? '');
    if (!_uuid.hasMatch(groupId) || !isSecret(secret) || name.isEmpty) {
      return null;
    }
    return Invite(groupId: groupId, secret: secret, hostName: name);
  }

  /// A name as shown to others: one line, trimmed, at most [nameLength]
  /// characters.
  static String cleanName(String name) {
    final line = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length <= nameLength ? line : line.substring(0, nameLength);
  }

  /// Whether [text] is a 128-bit secret as made by [newSecret].
  static bool isSecret(String text) {
    if (!RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(text)) return false;
    try {
      return base64Url.decode('$text==').length == 16;
    } on FormatException {
      return false;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Invite &&
      other.groupId == groupId &&
      other.secret == secret &&
      other.hostName == hostName;

  @override
  int get hashCode => Object.hash(groupId, secret, hostName);
}

/// 128 random bits from a secure source, as 22 characters of base64url.
String newSecret([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) source.nextInt(256)];
  return base64Url.encode(bytes).replaceAll('=', '');
}
