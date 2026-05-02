// Firebase Realtime Database over REST, for the relay tools on this
// computer. Reads android/app/google-services.json (not in git) and signs
// in anonymously, like the app.
import 'dart:convert';
import 'dart:io';

class FirebaseRest {
  FirebaseRest._(this.database, this.key, {this.namespace, this.auth});

  /// The local emulators of tool/check_firebase_rules.sh (project
  /// demo-tripping-rules): nothing leaves this computer.
  static FirebaseRest emulator() => FirebaseRest._(
    'http://127.0.0.1:9000',
    'fake-api-key',
    namespace: 'demo-tripping-rules-default-rtdb',
    auth: 'http://127.0.0.1:9099/identitytoolkit.googleapis.com',
  );

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
  final String? namespace;
  final String? auth;
  final client = HttpClient();

  /// A new anonymous user: (uid, token).
  Future<(String, String)> signUp() async {
    final (_, body) = await call(
      'POST',
      Uri.parse(
        '${auth ?? 'https://identitytoolkit.googleapis.com'}'
        '/v1/accounts:signUp?key=$key',
      ),
      {'returnSecureToken': true},
    );
    final account = jsonDecode(body) as Map<String, dynamic>;
    return (account['localId'] as String, account['idToken'] as String);
  }

  Uri at(String path, String? token) => Uri.parse(
    '$database/$path.json?'
    '${[if (namespace case final ns?) 'ns=$ns', if (token != null) 'auth=$token'].join('&')}',
  );

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
