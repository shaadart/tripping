import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'relay.dart';

/// Preserves the anonymous identity using native Firebase persistence, while
/// stopping the transport Auth instance's refresh timer on Android pause.
abstract final class GroupAuth {
  static const _channel = MethodChannel('tripping/group_auth');
  static Future<void> _pending = Future.value();

  static Future<String?> change(String method) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(null);
    }
    final result = _pending.then((_) async {
      try {
        return await _channel.invokeMethod<String>(method);
      } on PlatformException {
        throw const RelayUnavailable(
          'Could not restore or pause group sign-in',
        );
      }
    });
    _pending = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }
}
