import '../journey/journey.dart';

/// Whether the app may receive location fixes.
enum LocationAccess {
  granted,

  /// Permission refused; asking again may still work.
  denied,

  /// Permission refused for good; only the system settings can change it.
  deniedForever,

  /// Location is switched off for the whole device.
  serviceOff,

  /// Only approximate location (kilometres) is allowed: too coarse for a
  /// track.
  approximate,
}

/// Raised on a [LocationSource.watch] stream when fixes stop because access
/// was lost. The stream stays open and delivers fixes again if access
/// returns.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.reason);

  final LocationAccess reason;

  @override
  String toString() => 'LocationUnavailable(${reason.name})';
}

/// Where fixes come from: the platform in the app, a fake in tests.
abstract interface class LocationSource {
  /// Makes sure fixes can be delivered, prompting for permission only when
  /// the platform still allows a prompt. Never asks twice on its own.
  Future<LocationAccess> requestAccess();

  /// Opens the system screen where the user can fix [problem].
  Future<void> openSettingsFor(LocationAccess problem);

  /// Fixes for a journey in [mode] until the subscription is cancelled.
  ///
  /// Implementations must:
  /// - deliver only fresh fixes, never a cached position from before the
  ///   call;
  /// - report speed as null unless the platform measured it (D-013);
  /// - signal loss of access as a [LocationUnavailable] error and keep the
  ///   stream open.
  Stream<Fix> watch(JourneyMode mode);

  /// Where the platform last knew the phone to be, without asking for a new
  /// fix or for permission; null when it knows nothing or access is not
  /// granted. It may be old: never record it, and check [Fix.time] before
  /// presenting it as where the phone is now.
  Future<Fix?> lastKnown();
}
