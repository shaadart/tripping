import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/frame_stats.dart';
import 'app/history_screen.dart';
import 'app/record_screen.dart';
import 'app/settings.dart';
import 'app/share_gpx.dart';
import 'app/system_access.dart';
import 'app/theme.dart';
import 'bench/long_journey_bench.dart';
import 'history/journey_history.dart';
import 'journey/journey_store.dart';
import 'map/journey_map.dart';
import 'map/track_map.dart';
import 'recording/geolocator_location.dart';
import 'recording/location_source.dart';
import 'recording/raw_fix_log.dart';
import 'recording/recorder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (FrameStats.enabled) FrameStats.start();
  final highSun = ValueNotifier(false);
  runApp(TrippingApp(home: await _openHome(highSun), highSun: highSun));
}

/// The composition root: builds the long-lived objects once. Opening the
/// recorder also recovers a journey interrupted by a process death.
Future<Widget> _openHome(ValueNotifier<bool> highSun) async {
  try {
    final documents = await getApplicationDocumentsDirectory();
    final settings = await Settings.open(
      File('${documents.path}/settings.json'),
    );
    highSun.value = settings.highSun.value;
    settings.highSun.addListener(() => highSun.value = settings.highSun.value);
    // A bench build measures on its own database, never the owner's.
    final file = File(
      '${documents.path}/'
      '${LongJourneyBench.enabled ? LongJourneyBench.databaseName : 'journeys.sqlite'}',
    );
    final store = JourneyStore.file(file);
    if (LongJourneyBench.enabled) await LongJourneyBench.run(store, file);
    LocationSource location = const GeolocatorLocation();
    if (kDebugMode) {
      location = RawFixLog(location, File('${documents.path}/raw_fixes.jsonl'));
    }
    final recorder = await Recorder.open(store, location);
    return RecordScreen(
      recorder: recorder,
      location: location,
      system: const ChannelSystemAccess(),
      mapBuilder: (state, now) =>
          JourneyMap(state: state, store: store, now: now),
      waypoints: store,
      onToggleHighSun: () => settings.setHighSun(!settings.highSun.value),
      historyBuilder: (_) {
        final history = JourneyHistory(store);
        return HistoryScreen(
          history: history,
          trackMapBuilder: (track, waypoints) => TrackMap(
            track: track,
            waypoints: waypoints,
            onDrawn: LongJourneyBench.enabled
                ? LongJourneyBench.detailDrawn
                : null,
          ),
          onExport: (past) => shareGpx(history, past),
        );
      },
    );
  } catch (error) {
    return StartupFailure(error: error);
  }
}

class TrippingApp extends StatelessWidget {
  const TrippingApp({super.key, required this.home, this.highSun});

  final Widget home;

  /// When on, the high-sun look replaces both the light and the dark one.
  final ValueListenable<bool>? highSun;

  static final _off = ValueNotifier(false);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: highSun ?? _off,
      builder: (context, sun, _) => MaterialApp(
        title: 'Tripping',
        theme: trippingLook(sun ? Look.highSun : Look.light),
        darkTheme: trippingLook(sun ? Look.highSun : Look.dark),
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );
  }
}

/// Shown when the journey storage cannot be opened. Nothing was changed.
class StartupFailure extends StatelessWidget {
  const StartupFailure({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tripping can’t open its storage',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Nothing was recorded or changed. Restarting the phone may '
                'help.\n\n$error',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
