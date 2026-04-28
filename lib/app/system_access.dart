import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Why the app's previous process ended, as Android recorded it.
enum ExitCause {
  /// Stopped from Active apps (Task Manager) or force-stopped in Settings.
  user,

  /// Swiped away from recent apps while the process had nothing keeping it
  /// alive.
  swiped,
  crash,

  /// Closed by Android to free memory.
  memory,

  /// A permission was revoked, which ends the process.
  permission,

  /// Tripping was updated or reinstalled.
  update,

  /// Any other system decision, often battery management.
  system,
}

class LastExit {
  const LastExit(this.cause, this.at);

  final ExitCause cause;
  final DateTime at;
}

/// Android facts the recording screen needs and the location plugin does not
/// provide. Every method degrades to "unknown" (null or false) when the
/// answer is unavailable, for example on iOS or while no activity is attached.
abstract interface class SystemAccess {
  /// Whether Android shows Tripping's notifications.
  Future<bool?> notificationsEnabled();

  /// Asks to show notifications (Android 13+), at most as often as Android
  /// allows. Returns whether they are now shown.
  Future<bool?> requestNotifications();

  /// Whether battery use is set to Restricted, which stops recording as soon
  /// as Tripping leaves the screen.
  Future<bool> isBackgroundRestricted();

  /// Why recent processes ended, newest first, as far as Android recorded.
  Future<List<LastExit>> recentExits();

  /// Opens Tripping's page in the system settings.
  Future<void> openAppSettings();
}

/// [SystemAccess] over the `tripping/system` channel in MainActivity.kt.
class ChannelSystemAccess implements SystemAccess {
  const ChannelSystemAccess();

  static const _channel = MethodChannel('tripping/system');

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool?> notificationsEnabled() => _call<bool>('notificationsEnabled');

  @override
  Future<bool?> requestNotifications() => _call<bool>('requestNotifications');

  @override
  Future<bool> isBackgroundRestricted() async =>
      await _call<bool>('backgroundRestricted') ?? false;

  @override
  Future<List<LastExit>> recentExits() async {
    final exits = await _call<List<Object?>>('recentExits') ?? const [];
    return [
      for (final exit in exits.whereType<Map<Object?, Object?>>())
        if ((ExitCause.values.asNameMap()[exit['cause']], exit['at']) case (
          final ExitCause cause,
          final int at,
        ))
          LastExit(cause, DateTime.fromMillisecondsSinceEpoch(at, isUtc: true)),
    ];
  }

  @override
  Future<void> openAppSettings() => _call<void>('openAppSettings');

  static Future<T?> _call<T>(String method) async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null; // No activity attached right now.
    } on PlatformException {
      return null;
    }
  }
}
