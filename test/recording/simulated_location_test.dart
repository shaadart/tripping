import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/geo.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/recording/location_source.dart';
import 'package:tripping/recording/simulated_location.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);

void main() {
  test('a loop round the origin, never far from it', () {
    fakeAsync((async) {
      final location = SimulatedLocation(
        origin: (12.9763, 77.5929),
        speed: 8,
        clock: () => t0.add(async.elapsed),
      );
      final fixes = <Fix>[];
      final listening = location.watch(JourneyMode.road).listen(fixes.add);
      async.elapse(const Duration(minutes: 3));
      listening.cancel();
      expect(fixes, hasLength(180));
      for (final fix in fixes) {
        // The loop's far corner is 361 m away; GPS-like error adds a little.
        expect(
          metersBetween(12.9763, 77.5929, fix.latitude, fix.longitude),
          lessThan(400),
        );
        expect((fix.accuracy, fix.speed), (5, 8));
      }
      // 8 m/s for a second is 8 m, give or take the wandering error.
      expect(fixes[50].metersTo(fixes[51]), closeTo(8, 3));
      expect(fixes.first.heading, 90, reason: 'east first');
    });
  });

  test('access is granted without asking anything', () async {
    final location = SimulatedLocation(origin: (12.9763, 77.5929));
    expect(await location.requestAccess(), LocationAccess.granted);
    final known = (await location.lastKnown())!;
    expect(
      metersBetween(12.9763, 77.5929, known.latitude, known.longitude),
      lessThan(30),
    );
  });

  test('the flag is read strictly: no silent fallback to the real GPS', () {
    final location = SimulatedLocation.fromSpec('11.4183,76.7111,1.4');
    expect((location.origin, location.speed), ((11.4183, 76.7111), 1.4));
    expect(() => SimulatedLocation.fromSpec('cubbon'), throwsFormatException);
    expect(() => SimulatedLocation.fromSpec('95,10'), throwsFormatException);
  });

  test('normal builds have no simulation', () {
    expect(SimulatedLocation.enabled, isFalse);
  });
}
