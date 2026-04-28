import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripping/app/offline_maps_screen.dart';
import 'package:tripping/app/theme.dart';
import 'package:tripping/map/offline_area.dart';
import 'package:tripping/map/offline_maps.dart';

/// Offline areas held in memory; downloads are driven by the test.
class FakeOfflineMaps implements OfflineMaps {
  FakeOfflineMaps([List<OfflineMap>? areas]) : areas = areas ?? [];

  final List<OfflineMap> areas;
  final downloads = <(String, Area)>[];
  StreamController<double>? running;

  @override
  Future<List<OfflineMap>> list() async => [...areas];

  @override
  Stream<double> download(String name, Area area) {
    downloads.add((name, area));
    running = StreamController<double>();
    return running!.stream;
  }

  @override
  Future<void> delete(int id) async => areas.removeWhere((a) => a.id == id);
}

const city = (south: 12.84, west: 77.45, north: 13.11, east: 77.73);
const state = (south: 11.5, west: 74.0, north: 18.5, east: 78.6);

OfflineMap saved(int id, String name) => OfflineMap(
  id: id,
  name: name,
  area: city,
  release: 'r1',
  savedAt: DateTime.utc(2026, 10, 28, 12),
  bytes: 4404019,
  complete: true,
  progress: 1,
);

/// The download button: `FilledButton.icon` builds a subclass, which an
/// exact type finder would miss.
Finder downloadButton() => find.ancestor(
  of: find.text('Download'),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

void main() {
  late Area shown;

  Future<void> show(WidgetTester tester, FakeOfflineMaps maps) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: trippingTheme(Brightness.light),
        home: OfflineMapsScreen(
          maps: maps,
          areaMapBuilder: (onArea) => _RestingMap(() => onArea(shown)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => shown = city);

  testWidgets('explains offline maps before there are any', (tester) async {
    await show(tester, FakeOfflineMaps());
    expect(find.textContaining('No offline maps yet'), findsOneWidget);
  });

  testWidgets('lists saved areas with their size and day', (tester) async {
    await show(tester, FakeOfflineMaps([saved(1, 'Spiti valley')]));
    expect(find.text('Spiti valley'), findsOneWidget);
    expect(find.textContaining('4.2 MB · saved'), findsOneWidget);
  });

  testWidgets('deleting asks first', (tester) async {
    final maps = FakeOfflineMaps([saved(1, 'Spiti valley')]);
    await show(tester, maps);
    await tester.tap(find.byTooltip('Delete Spiti valley'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(maps.areas, hasLength(1));

    await tester.tap(find.byTooltip('Delete Spiti valley'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(maps.areas, isEmpty);
    expect(find.textContaining('No offline maps yet'), findsOneWidget);
  });

  testWidgets('an area that fits is estimated, named and downloaded', (
    tester,
  ) async {
    final maps = FakeOfflineMaps();
    await show(tester, maps);
    await tester.tap(find.text('Download an area'));
    await tester.pumpAndSettle();
    expect(find.textContaining('map tiles · roughly'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Bengaluru');
    await tester.tap(downloadButton());
    await tester.pump();
    expect(maps.downloads.single, ('Bengaluru', city));

    maps.running!.add(0.5);
    await tester.pump();
    expect(find.text('Downloading… 50 %'), findsOneWidget);

    maps.areas.add(saved(2, 'Bengaluru'));
    maps.running!.add(1);
    unawaited(maps.running!.close());
    await tester.pumpAndSettle();
    expect(find.text('Saved for offline use'), findsOneWidget);
    expect(find.text('Bengaluru'), findsOneWidget);
  });

  testWidgets('an area too big for one download cannot be started', (
    tester,
  ) async {
    shown = state;
    final maps = FakeOfflineMaps();
    await show(tester, maps);
    await tester.tap(find.text('Download an area'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too big for one download'), findsOneWidget);
    expect(tester.widget<FilledButton>(downloadButton()).onPressed, isNull);
  });

  testWidgets('a failed download says why and can be retried', (tester) async {
    final maps = FakeOfflineMaps();
    await show(tester, maps);
    await tester.tap(find.text('Download an area'));
    await tester.pumpAndSettle();
    await tester.tap(downloadButton());
    await tester.pump();
    maps.running!.addError(
      const OfflineMapError('Downloading needs an internet connection.'),
    );
    unawaited(maps.running!.close());
    await tester.pumpAndSettle();
    expect(
      find.text('Downloading needs an internet connection.'),
      findsOneWidget,
    );
    expect(downloadButton(), findsOneWidget);
  });
}

/// Like the real map: reports its area once, when it comes to rest.
class _RestingMap extends StatefulWidget {
  const _RestingMap(this.report);

  final VoidCallback report;

  @override
  State<_RestingMap> createState() => _RestingMapState();
}

class _RestingMapState extends State<_RestingMap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.report());
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
