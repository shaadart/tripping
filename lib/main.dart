import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/record_screen.dart';
import 'app/system_access.dart';
import 'app/theme.dart';
import 'journey/journey_store.dart';
import 'recording/geolocator_location.dart';
import 'recording/location_source.dart';
import 'recording/raw_fix_log.dart';
import 'recording/recorder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TrippingApp(home: await _openHome()));
}

/// The composition root: builds the long-lived objects once. Opening the
/// recorder also recovers a journey interrupted by a process death.
Future<Widget> _openHome() async {
  try {
    final documents = await getApplicationDocumentsDirectory();
    final store = JourneyStore.file(File('${documents.path}/journeys.sqlite'));
    LocationSource location = const GeolocatorLocation();
    if (kDebugMode) {
      location = RawFixLog(location, File('${documents.path}/raw_fixes.jsonl'));
    }
    final recorder = await Recorder.open(store, location);
    return RecordScreen(
      recorder: recorder,
      location: location,
      system: const ChannelSystemAccess(),
    );
  } catch (error) {
    return StartupFailure(error: error);
  }
}

class TrippingApp extends StatelessWidget {
  const TrippingApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tripping',
      theme: trippingTheme(Brightness.light),
      darkTheme: trippingTheme(Brightness.dark),
      debugShowCheckedModeBanner: false,
      home: home,
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
