import 'dart:async';
import 'dart:io';

import 'package:tripping/app/system_access.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/recording/location_source.dart';

final t0 = DateTime.utc(2026, 10, 28, 6);
const metersPerDegree = 111195.08;

/// A walker heading north at 1.5 m/s with ±3 m fixes.
Fix walkFix(int second, {double startNorth = 0}) => Fix(
  time: t0.add(Duration(seconds: second)),
  latitude: 32 + (startNorth + 1.5 * second) / metersPerDegree,
  longitude: 77,
  accuracy: 3,
  speed: 1.5,
);

class FakeLocation implements LocationSource {
  LocationAccess access = LocationAccess.granted;
  int requests = 0;
  final settingsOpened = <LocationAccess>[];
  StreamController<Fix>? _fixes;

  bool get listening => _fixes?.hasListener ?? false;

  @override
  Future<LocationAccess> requestAccess() async {
    requests++;
    return access;
  }

  @override
  Future<void> openSettingsFor(LocationAccess problem) async =>
      settingsOpened.add(problem);

  /// Delivers synchronously, so a fix emitted before `settled()` is always
  /// queued before it.
  @override
  Stream<Fix> watch(JourneyMode mode) =>
      (_fixes = StreamController(sync: true)).stream;

  void emit(Fix fix) => _fixes!.add(fix);

  void lose(LocationAccess reason) =>
      _fixes!.addError(LocationUnavailable(reason));
}

/// A real store whose appends can be made to fail.
class FlakyStore extends JourneyStore {
  FlakyStore(super.executor);

  bool failAppends = false;

  @override
  Future<AppendResult> append(int journeyId, Fix fix) async {
    if (failAppends) throw const FileSystemException('No space left');
    return super.append(journeyId, fix);
  }
}

/// Android facts on demand, with a record of what the screen asked for.
class FakeSystemAccess implements SystemAccess {
  bool? notificationsShown = true;
  bool? grantOnRequest = true;
  bool restricted = false;
  List<LastExit> exits = const [];
  int notificationRequests = 0;
  int appSettingsOpened = 0;

  @override
  Future<bool?> notificationsEnabled() async => notificationsShown;

  @override
  Future<bool?> requestNotifications() async {
    notificationRequests++;
    return notificationsShown = grantOnRequest;
  }

  @override
  Future<bool> isBackgroundRestricted() async => restricted;

  @override
  Future<List<LastExit>> recentExits() async => exits;

  @override
  Future<void> openAppSettings() async => appSettingsOpened++;
}
