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

/// Answers every search with [camp]; remembers where it was asked from.
class NearSearch implements PlaceSearch {
  (double?, double?)? near;

  @override
  Future<List<Place>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
  }) async {
    near = (nearLatitude, nearLongitude);
    return [camp];
  }
}

/// Plans by road, or fails as the test says.
class StubRouter implements RouteSource {
  RouteError? failWith;
  double seconds = 1500;
  double meters = 6400;

  @override
  Future<PlannedRoute> route(
    (double, double) from,
    (double, double) to,
    JourneyMode mode, {
    required DateTime at,
  }) async {
    if (failWith case final error?) throw error;
    return PlannedRoute(
      kind: RouteKind.road,
      provider: 'stub',
      computedAt: at,
      meters: meters,
      seconds: seconds,
      points: [from, (32.03, 77.01), to],
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
    expect(find.text('6.40 km by road · about 25 min'), findsOneWidget);
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
    expect(find.text('0.01 km by road · under a minute'), findsOneWidget);
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
    expect(find.text('6.40 km by road · about 25 min'), findsOneWidget);
    await cleanUp(tester);
  });
}
