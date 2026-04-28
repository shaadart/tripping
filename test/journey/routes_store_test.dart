import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';

final t0 = DateTime.utc(2026, 10, 29, 6);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late JourneyStore store;
  late int journey;

  setUp(() async {
    store = JourneyStore(NativeDatabase.memory());
    journey = (await store.startJourney(JourneyMode.road, at: t0)).id;
  });
  tearDown(() => store.close());

  Future<void> goTo(String name) => store.setDestination(
    journey,
    name: name,
    detail: 'Bengaluru',
    latitude: 12.97,
    longitude: 77.59,
  );

  Future<void> routeThere() => store.saveRoute(
    journey,
    kind: RouteKind.road,
    provider: 'valhalla',
    computedAt: t0,
    meters: 8669,
    seconds: 1776,
    geometry: 'abc',
  );

  test('a destination first, then the way there', () async {
    await goTo('Cubbon Park');
    var route = (await store.routeOf(journey))!;
    expect(
      (route.destination, route.destinationDetail),
      ('Cubbon Park', 'Bengaluru'),
    );
    expect(route.kind, isNull);

    await routeThere();
    route = (await store.routeOf(journey))!;
    expect(
      (route.kind, route.provider, route.meters, route.seconds),
      (RouteKind.road, 'valhalla', 8669, 1776),
    );
    expect(route.computedAt, t0);
  });

  test('a new destination drops the way to the old one', () async {
    await goTo('Cubbon Park');
    await routeThere();
    await goTo('Lalbagh');
    final route = (await store.routeOf(journey))!;
    expect(route.destination, 'Lalbagh');
    expect([
      route.kind,
      route.provider,
      route.computedAt,
      route.meters,
      route.seconds,
      route.geometry,
    ], everyElement(isNull));
  });

  test('the route goes with its journey, and can be cleared', () async {
    await goTo('Cubbon Park');
    await store.clearDestination(journey);
    expect(await store.routeOf(journey), isNull);

    await goTo('Cubbon Park');
    await store.end(journey, at: t0.add(const Duration(hours: 1)));
    await store.deleteJourney(journey);
    expect(await store.routeOf(journey), isNull);
  });

  test('watching sees the route arrive', () async {
    final seen = <RouteKind?>[];
    final watching = store
        .watchRoute(journey)
        .listen((route) => seen.add(route?.kind));
    await pumpEventQueue();
    await goTo('Cubbon Park');
    await pumpEventQueue();
    await routeThere();
    await pumpEventQueue();
    await watching.cancel();
    expect(seen, [null, null, RouteKind.road]);
  });

  test(
    'recent places: newest first, chosen again moves up, kept few',
    () async {
      Future<void> remember(String name, int minute) => store.rememberPlace(
        name: name,
        latitude: 12 + minute / 100,
        longitude: 77,
        at: t0.add(Duration(minutes: minute)),
        keep: 3,
      );
      await remember('A', 1);
      await remember('B', 2);
      await remember('C', 3);
      await store.rememberPlace(
        name: 'A',
        latitude: 12.01,
        longitude: 77,
        at: t0.add(const Duration(minutes: 4)),
        keep: 3,
      );
      await remember('D', 5);
      expect((await store.latestPlaces()).map((p) => p.name), ['D', 'A', 'C']);
    },
  );
}
