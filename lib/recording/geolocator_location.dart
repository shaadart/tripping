import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../journey/journey.dart';
import 'location_source.dart';

/// [LocationSource] backed by the platform through the geolocator plugin.
///
/// The one Flutter-dependent file in `recording/` (D-006): everything it
/// hands on is a plain [Fix].
class GeolocatorLocation implements LocationSource {
  const GeolocatorLocation();

  @override
  Future<LocationAccess> requestAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final access = accessFrom(permission);
    if (access != LocationAccess.granted) return access;
    return await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced
        ? LocationAccess.approximate
        : LocationAccess.granted;
  }

  @override
  Future<void> openSettingsFor(LocationAccess problem) async {
    switch (problem) {
      case LocationAccess.serviceOff:
        await Geolocator.openLocationSettings();
      case LocationAccess.denied ||
          LocationAccess.deniedForever ||
          LocationAccess.approximate:
        await Geolocator.openAppSettings();
      case LocationAccess.granted:
        break;
    }
  }

  @override
  Stream<Fix> watch(JourneyMode mode) {
    late final StreamController<Fix> fixes;
    StreamSubscription<Position>? positions;
    StreamSubscription<ServiceStatus>? service;

    void stopPositions() {
      unawaited(positions?.cancel());
      positions = null;
    }

    void startPositions() {
      positions =
          Geolocator.getPositionStream(
            locationSettings: settingsFor(mode),
          ).listen(
            (position) => fixes.add(fixFrom(position)),
            onError: (Object error) {
              switch (error) {
                case LocationServiceDisabledException():
                  // Restarted by the service status listener when it is back on.
                  stopPositions();
                  fixes.addError(
                    const LocationUnavailable(LocationAccess.serviceOff),
                  );
                case PermissionDeniedException():
                  fixes.addError(
                    const LocationUnavailable(LocationAccess.denied),
                  );
                default:
                  fixes.addError(error);
              }
            },
          );
    }

    fixes = StreamController<Fix>(
      onListen: () {
        startPositions();
        service = Geolocator.getServiceStatusStream().listen(
          (status) {
            if (status == ServiceStatus.disabled) {
              if (positions == null) return;
              stopPositions();
              fixes.addError(
                const LocationUnavailable(LocationAccess.serviceOff),
              );
            } else if (positions == null) {
              startPositions();
            }
          },
          // Not every platform reports service changes; position errors
          // still do.
          onError: (Object _) {},
        );
      },
      onCancel: () async {
        await positions?.cancel();
        await service?.cancel();
      },
    );
    return fixes.stream;
  }

  /// One fix per second on the road, every two seconds on foot. Never a
  /// cached position from before the request (`maxUpdateAge: zero`).
  static LocationSettings settingsFor(JourneyMode mode) {
    final road = mode == JourneyMode.road;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: Duration(seconds: road ? 1 : 2),
        maxUpdateAge: Duration.zero,
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: road
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.best,
        activityType: road
            ? ActivityType.automotiveNavigation
            : ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
      ),
      _ => const LocationSettings(accuracy: LocationAccuracy.high),
    };
  }
}

/// Converts a platform position. Values the platform did not measure become
/// null, never geolocator's 0.0 placeholders: a fabricated speed of zero
/// would hide real slow movement (D-013).
Fix fixFrom(Position position) => Fix(
  time: position.timestamp.toUtc(),
  latitude: position.latitude,
  longitude: position.longitude,
  accuracy: position.hasAccuracy ? position.accuracy : null,
  altitude: position.hasAltitude ? position.altitude : null,
  altitudeAccuracy: position.hasAltitudeAccuracy
      ? position.altitudeAccuracy
      : null,
  speed: position.hasSpeed ? position.speed : null,
  heading: position.hasHeading ? position.heading : null,
);

LocationAccess accessFrom(LocationPermission permission) =>
    switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationAccess.denied,
    };
