// Firebase Realtime Database over REST, for the relay tools on this
// computer. Reads android/app/google-services.json (not in git) and signs
// in anonymously, like the app.
import 'dart:convert';
import 'dart:io';

class FirebaseRest {
  FirebaseRest._(this.database, this.key);

  static FirebaseRest fromSettings() {
    final settings =
        jsonDecode(File('android/app/google-services.json').readAsStringSync())
            as Map<String, dynamic>;
    return FirebaseRest._(
      settings['project_info']['firebase_url'] as String,
      settings['client'][0]['api_key'][0]['current_key'] as String,
    );
  }

  final String database;
  final String key;
  final client = HttpClient();

  /// A new anonymous user: (uid, token).
  Future<(String, String)> signUp() async {
    final (_, body) = await call(
      'POST',
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$key',
      ),
      {'returnSecureToken': true},
    );
    final account = jsonDecode(body) as Map<String, dynamic>;
    return (account['localId'] as String, account['idToken'] as String);
  }

  Uri at(String path, String? token) =>
      Uri.parse('$database/$path.json${token == null ? '' : '?auth=$token'}');

  /// (status, body) of a request; never throws for an HTTP error.
  Future<(int, String)> call(String method, Uri uri, [Object? body]) async {
    final request = await client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('User-Agent', 'Tripping relay tool');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  }

  static const now = {'.sv': 'timestamp'};
}
