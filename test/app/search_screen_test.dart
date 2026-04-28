import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/search_screen.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/places/place.dart';
import 'package:tripping/places/place_search.dart';

const lalbagh = Place(
  name: 'Lalbagh',
  detail: 'Bengaluru, Karnataka, India',
  latitude: 12.9507,
  longitude: 77.5848,
);

/// Answers searches as the test says; counts what it is asked.
class FakeSearch implements PlaceSearch {
  final asked = <String>[];
  Future<List<Place>> Function(String query) answer = (_) async => [lalbagh];

  @override
  Future<List<Place>> search(
    String query, {
    double? nearLatitude,
    double? nearLongitude,
  }) {
    asked.add(query);
    return answer(query);
  }
}

void main() {
  late FakeSearch search;
  Place? chosen;

  setUp(() {
    search = FakeSearch();
    chosen = null;
  });

  Future<void> show(
    WidgetTester tester, {
    List<Place> recent = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              chosen = await Navigator.of(context).push<Place>(
                MaterialPageRoute(
                  builder: (_) => SearchScreen(
                    search: search,
                    recent: () async => recent,
                    near: (12.9763, 77.5929),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks once typing pauses, not on every key', (tester) async {
    await show(tester);
    for (final text in ['l', 'la', 'lal', 'lalb', 'lalba']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(search.asked, ['lalba']);
    expect(find.text('Lalbagh'), findsOneWidget);
    expect(find.textContaining('km away'), findsOneWidget);
  });

  testWidgets('the field keeps its text while a slow answer comes', (
    tester,
  ) async {
    final slow = Completer<List<Place>>();
    search.answer = (_) => slow.future;
    await show(tester);
    await tester.enterText(find.byType(TextField), 'lalbagh');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(TextField, 'lalbagh'), findsOneWidget);
    slow.complete([lalbagh]);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.widgetWithText(TextField, 'lalbagh'), findsOneWidget);
  });

  testWidgets('a chosen result comes back', (tester) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), 'lalbagh');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lalbagh'));
    await tester.pumpAndSettle();
    expect(chosen, lalbagh);
  });

  testWidgets('an older answer never replaces a newer one', (tester) async {
    final slow = Completer<List<Place>>();
    search.answer = (query) => query == 'lalb'
        ? slow.future
        : Future.value(const [
            Place(name: 'Lalbagh West Gate', latitude: 12.95, longitude: 77.58),
          ]);
    await show(tester);
    await tester.enterText(find.byType(TextField), 'lalb');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'lalbagh west');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    slow.complete([lalbagh]);
    await tester.pumpAndSettle();
    expect(find.text('Lalbagh West Gate'), findsOneWidget);
    expect(find.text('Lalbagh'), findsNothing);
  });

  testWidgets('recent places show while nothing is typed', (tester) async {
    await show(tester, recent: [lalbagh]);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Lalbagh'), findsOneWidget);
    expect(search.asked, isEmpty);
  });

  testWidgets('offline, it points to the map instead', (tester) async {
    search.answer = (_) async =>
        throw const SearchError('Search needs a connection.', offline: true);
    await show(tester);
    await tester.enterText(find.byType(TextField), 'lalbagh');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Search needs a connection'), findsOneWidget);
    expect(find.textContaining('long-press the place'), findsOneWidget);
  });

  testWidgets('credits Photon and OpenStreetMap', (tester) async {
    await show(tester);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
  });
}
