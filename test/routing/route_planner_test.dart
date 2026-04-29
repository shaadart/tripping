import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/places/place.dart';
import 'package:tripping/places/polyline.dart';
import 'package:tripping/routing/route_planner.dart';
import 'package:tripping/routing/router.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);
const here = (12.9763, 77.5929);
const park = Place(
  name: 'Lalbagh',
  detail: 'Bengaluru',
  latitude: 12.9507,
  longitude: 77.5848,
);

/// Answers the way the test says.
class FakeRouter implements RouteSource {
  Future<PlannedRoute> Function()? answer;
  final asked = <JourneyMode>[];

  @override
  Future<PlannedRoute> route(
    (double, double) from,
    (double, double) to,
    JourneyMode mode, {
    required DateTime at,
  }) {
    asked.add(mode);
    return answer!();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late JourneyStore store;
  late FakeRouter router;
  late RoutePlanner planner;
  late int journey;

  setUp(() async {
    store = JourneyStore(NativeDatabase.memory());
    router = FakeRouter();
    planner = RoutePlanner(store, router, clock: () => t0);
    journey = (await store.startJourney(JourneyMode.road, at: t0)).id;
  });
  tearDown(() => store.close());

  PlannedRoute road() => PlannedRoute(
    kind: RouteKind.road,
    provider: 'valhalla',
    computedAt: t0,
    meters: 4100,
    seconds: 900,
    points: const [here, (12.96, 77.58), (12.9507, 77.5848)],
  );

  test('a road route is kept with the journey, line and all', () async {
    router.answer = () async => road();
    await planner.goTo(journey, park);
    expect(await planner.plan(journey, here, JourneyMode.road), isNull);

    final route = (await store.routeOf(journey))!;
    expect(
      (route.kind, route.provider, route.meters, route.seconds),
      (RouteKind.road, 'valhalla', 4100, 900),
    );
    expect(decodePolyline(route.geometry!), road().points);
    expect(router.asked, [JourneyMode.road]);
  });

  test(
    'without a connection the way is a straight line, and says why',
    () async {
      router.answer = () async => throw const RouteError(
        'No road route without a connection.',
        offline: true,
      );
      await planner.goTo(journey, park);
      final why = await planner.plan(journey, here, JourneyMode.road);

      expect(why?.offline, isTrue);
      final route = (await store.routeOf(journey))!;
      expect(route.kind, RouteKind.straight);
      expect(route.provider, 'straight line');
      expect(route.seconds, isNull);
      expect(decodePolyline(route.geometry!), [
        here,
        (park.latitude, park.longitude),
      ]);
    },
  );

  test(
    'a new way that fails keeps the old road, not a straight line',
    () async {
      router.answer = () async => road();
      await planner.goTo(journey, park);
      await planner.plan(journey, here, JourneyMode.road);

      router.answer = () async => throw const RouteError(
        'No road route without a connection.',
        offline: true,
      );
      final why = await planner.plan(
        journey,
        (12.99, 77.6),
        JourneyMode.road,
        keepOnFailure: true,
      );
      expect(why?.offline, isTrue);
      final route = (await store.routeOf(journey))!;
      expect(route.kind, RouteKind.road);
      expect(decodePolyline(route.geometry!), road().points);
    },
  );

  test('a route for a destination changed meanwhile is not kept', () async {
    final answer = Completer<PlannedRoute>();
    router.answer = () => answer.future;
    await planner.goTo(journey, park);
    final planning = planner.plan(journey, here, JourneyMode.road);
    await planner.goTo(
      journey,
      const Place(name: 'Elsewhere', latitude: 13.1, longitude: 77.7),
    );
    answer.complete(road());
    await planning;

    final route = (await store.routeOf(journey))!;
    expect(route.destination, 'Elsewhere');
    expect(route.kind, isNull);
  });

  test(
    'pause invalidates a late answer even when the destination is unchanged',
    () async {
      final answer = Completer<PlannedRoute>();
      final asked = Completer<void>();
      router.answer = () {
        asked.complete();
        return answer.future;
      };
      await planner.goTo(journey, park);
      final planning = planner.plan(journey, here, JourneyMode.road);
      await asked.future;
      planner.cancelPending();
      answer.complete(road());
      await planning;
      expect((await store.routeOf(journey))!.kind, isNull);
    },
  );

  test('a waypoint headed for is not kept among recent places', () async {
    await planner.goTo(journey, park, remember: false);
    expect(await planner.recent(), isEmpty);
    expect((await store.routeOf(journey))!.destination, 'Lalbagh');
  });

  test('chosen places are remembered; a bare map point is not', () async {
    router.answer = () async => road();
    await planner.goTo(journey, park);
    await planner.goTo(
      journey,
      const Place(name: mapPoint, latitude: 13, longitude: 77.6),
    );
    expect(await planner.recent(), [park]);
  });

  test('no destination, nothing planned', () async {
    router.answer = () async => fail('should not be asked');
    expect(await planner.plan(journey, here, JourneyMode.road), isNull);
  });
}
