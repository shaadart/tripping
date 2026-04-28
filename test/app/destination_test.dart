import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/record_screen.dart';
import 'package:tripping/app/search_screen.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/journey/journey.dart';
import 'package:tripping/journey/journey_store.dart';
import 'package:tripping/places/place.dart';
import 'package:tripping/places/place_search.dart';
import 'package:tripping/recording/recorder.dart';
import 'package:tripping/routing/route_planner.dart';
import 'package:tripping/routing/router.dart';

import '../support/fakes.dart';

// North of the walk in fakes.dart, which starts at 32° N, 77° E.
const camp = Place(
  name: 'Camp',
  detail: 'Upper valley',
  latitude: 32.05,
  longitude: 77,
);

/// Answers every search with [answer]; remembers where it was asked from.
class NearSearch implements PlaceSearch {
  (double?, double?)? near;
  Place answer = camp;

  @override
  Future<List<Place>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
  }) async {
    near = (nearLatitude, nearLongitude);
    return [answer];
  }
}

/// Plans a road straight there, or fails as the test says.
class StubRouter implements RouteSource {
  RouteError? failWith;
  int asked = 0;
  double seconds = 1500;
  double meters = 6400;

  @override
  Future<PlannedRoute> route(
    (double, double) from,
    (double, double) to,
    JourneyMode mode, {
    required DateTime at,
  }) async {
    asked++;
    if (failWith case final error?) throw error;
    return PlannedRoute(
      kind: RouteKind.road,
      provider: 'stub',
      computedAt: at,
      meters: meters,
      seconds: seconds,
      points: [from, to],
    );
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late JourneyStore store;
  late FakeLocation location;
  late NearSearch search;
  late StubRouter router;
  late Recorder recorder;
  late DateTime now;

  setUp(() {
    store = JourneyStore(NativeDatabase.memory());
    location = FakeLocation();
    search = NearSearch();
    router = StubRouter();
    now = t0;
  });

  Future<void> act(WidgetTester tester, Future<void> Function() work) async {
    await tester.runAsync(() async {
      await work();
      await recorder.settled();
      // The route is written and watched through the database.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  Future<void> show(WidgetTester tester) async {
    await tester.runAsync(() async {
      recorder = await Recorder.open(store, location, clock: () => now);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingTheme(Brightness.light),
        home: RecordScreen(
          recorder: recorder,
          location: location,
          system: FakeSystemAccess(),
          mapBuilder: (_, _) => const SizedBox.expand(),
          places: search,
          planner: RoutePlanner(store, router, clock: () => now),
          clock: () => now,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Database work begun under the test clock must finish before closing.
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await recorder.close();
      await store.close();
    });
  }

  /// Walks [east] metres east of the start, [second]s in, at 1.5 m/s.
  Fix eastFix(int second, double east) => Fix(
    time: t0.add(Duration(seconds: second)),
    latitude: 32,
    longitude: 77 + east / (metersPerDegree * cos(32 * pi / 180)),
    accuracy: 3,
    speed: 1.5,
  );

  /// Searches from the idle screen and picks [camp].
  Future<void> pickCamp(WidgetTester tester) async {
    await tester.tap(find.text('Search a place'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'camp');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camp'));
    await tester.pumpAndSettle();
  }

  testWidgets('before a journey, search favours the last known position', (
    tester,
  ) async {
    location.known = walkFix(0);
    now = t0.add(const Duration(minutes: 2));
    await show(tester);
    await pickCamp(tester);
    expect(search.near, (32.0, 77.0));
    expect(find.text('To Camp'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('an old position favours results but gives no distances', (
    tester,
  ) async {
    location.known = walkFix(0);
    now = t0.add(const Duration(hours: 3));
    await show(tester);
    await tester.tap(find.text('Search a place'));
    await tester.pumpAndSettle();
    final screen = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(screen.near, (32.0, 77.0));
    expect(screen.distances, isFalse);
    await tester.enterText(find.byType(TextField), 'camp');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Camp'), findsOneWidget);
    expect(find.textContaining('km away'), findsNothing);
    await cleanUp(tester);
  });

  testWidgets('the way is planned by road at the first fix', (tester) async {
    await show(tester);
    await pickCamp(tester);
    await act(tester, () async => tester.tap(find.text('Road journey')));
    expect(find.text('To Camp'), findsOneWidget);
    expect(find.text('The way is planned at the first GPS fix.'), findsOne);

    await act(tester, () async => location.emit(walkFix(0)));
    await act(tester, () async {});
    expect(
      find.textContaining('6.40 km to go by road · about 25 min, arriving'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsNothing);
    await cleanUp(tester);
  });

  testWidgets('a way of seconds is not "about 0 min"', (tester) async {
    router.seconds = 20;
    router.meters = 9;
    await show(tester);
    await pickCamp(tester);
    await act(tester, () async => tester.tap(find.text('Road journey')));
    await act(tester, () async => location.emit(walkFix(0)));
    await act(tester, () async {});
    expect(
      find.textContaining('0.01 km to go by road · under a minute'),
      findsOneWidget,
    );
    await cleanUp(tester);
  });

  testWidgets('without a road route it says the line is straight', (
    tester,
  ) async {
    router.failWith = const RouteError(
      'Road routes need a connection.',
      offline: true,
    );
    await show(tester);
    await pickCamp(tester);
    await act(tester, () async => tester.tap(find.text('Road journey')));
    await act(tester, () async => location.emit(walkFix(0)));
    await act(tester, () async {});
    expect(
      find.textContaining('in a straight line, not by road'),
      findsOneWidget,
    );
    expect(find.textContaining('Road routes need a connection.'), findsOne);

    router.failWith = null;
    await act(tester, () async => tester.tap(find.text('Try again')));
    await act(tester, () async {});
    expect(
      find.textContaining('6.40 km to go by road · about 25 min, arriving'),
      findsOneWidget,
    );
    await cleanUp(tester);
  });

  testWidgets('off the road for 20 s, it says so and finds a new way', (
    tester,
  ) async {
    await show(tester);
    await pickCamp(tester);
    await act(tester, () async => tester.tap(find.text('Road journey')));
    await act(tester, () async => location.emit(walkFix(0)));
    await act(tester, () async {});
    expect(router.asked, 1);

    // East, away from a road that runs north: 50 m away after 34 s.
    for (var s = 1; s <= 50; s++) {
      await act(tester, () async => location.emit(eastFix(s, 1.5 * s)));
    }
    expect(find.textContaining('Off the route'), findsNothing);
    expect(router.asked, 1);
    for (var s = 51; s <= 56; s++) {
      await act(tester, () async => location.emit(eastFix(s, 1.5 * s)));
    }
    await act(tester, () async {});
    expect(router.asked, 2);
    // The new way starts here, so it is on it again.
    expect(find.textContaining('Off the route'), findsNothing);
    expect(find.textContaining('to go by road'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('off the road without a connection, the old road stays', (
    tester,
  ) async {
    await show(tester);
    await pickCamp(tester);
    await act(tester, () async => tester.tap(find.text('Road journey')));
    await act(tester, () async => location.emit(walkFix(0)));
    await act(tester, () async {});
    router.failWith = const RouteError(
      'Road routes need a connection.',
      offline: true,
    );
    for (var s = 1; s <= 56; s++) {
      await act(tester, () async => location.emit(eastFix(s, 1.5 * s)));
    }
    await act(tester, () async {});
    expect(router.asked, 2);
    expect(find.textContaining('Off the route · 5.'), findsOneWidget);
    expect(find.textContaining('Road routes need a connection.'), findsOne);
    expect(find.text('Try again'), findsOneWidget);
    final journey = (recorder.state as Recording).journey.id;
    final route = await tester.runAsync(() => store.routeOf(journey));
    expect(route?.kind, RouteKind.road);
    await cleanUp(tester);
  });

  testWidgets('near the destination it says you have arrived', (tester) async {
    search.answer = const Place(
      name: 'Gate',
      latitude: 32 + 40 / metersPerDegree,
      longitude: 77,
    );
    await show(tester);
    await tester.tap(find.text('Search a place'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gate');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gate'));
    await tester.pumpAndSettle();
    await act(tester, () async => tester.tap(find.text('Road journey')));
    await act(tester, () async => location.emit(walkFix(0)));
    await act(tester, () async {});
    expect(find.text('You have arrived.'), findsOneWidget);
    await cleanUp(tester);
  });
}
