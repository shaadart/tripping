import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../map/offline_area.dart';
import '../map/offline_maps.dart';
import '../recording/recorder.dart';
import 'figure.dart';
import 'format.dart';
import 'record_status.dart';

/// How long a fix's speed still counts as the speed now.
const speedFreshFor = Duration(seconds: 5);

/// The numbers that matter for the kind of journey: on the road, speed
/// first; on an expedition, time and moving time.
class Readout extends StatelessWidget {
  const Readout({super.key, required this.state, required this.now});

  final RecorderState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (journey, progress) = switch (state) {
      Recording(:final journey, :final progress) ||
      Paused(:final journey, :final progress) ||
      Interrupted(:final journey, :final progress) => (journey, progress),
      Idle() => throw StateError('No journey to read out'),
    };
    final time = Figure(
      value: clockTime(progress.elapsedAt(now)),
      label: 'Time',
    );
    final distance = Figure(
      value: kilometres(progress.meters),
      label: 'Distance',
    );
    final row = LayoutBuilder(
      builder: (context, box) {
        final columns = MediaQuery.textScalerOf(context).scale(24) > 34 ? 1 : 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final figure in switch (journey.mode) {
              JourneyMode.road => [
                Figure(value: speedText(_freshSpeed()), label: 'Speed'),
                distance,
                time,
              ],
              JourneyMode.expedition => [
                time,
                distance,
                Figure(value: clockTime(progress.movingTime), label: 'Moving'),
              ],
            })
              SizedBox(
                width: (box.maxWidth - 12 * (columns - 1)) / columns,
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textTheme: Theme.of(context).textTheme.copyWith(
                      headlineMedium: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 24),
                    ),
                  ),
                  child: figure,
                ),
              ),
          ],
        );
      },
    );
    final (climb, descent) = (progress.climb, progress.descent);
    if (journey.mode != JourneyMode.expedition ||
        climb == null ||
        descent == null) {
      return row;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 4),
        Text(
          'Climb ${climbText(climb)} · Descent ${climbText(descent)}',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// The GPS's own speed from a fix at most a few seconds old; anything
  /// older is not the speed now.
  double? _freshSpeed() => switch (state) {
    Recording(:final latestFix?, :final latestFixArrivedAt?)
        when now.difference(latestFixArrivedAt) <= speedFreshFor =>
      latestFix.speed,
    _ => null,
  };
}

/// Says so when the journey is inside an area saved for offline use: the
/// map there keeps working without signal.
class SavedHere extends StatelessWidget {
  const SavedHere({super.key, required this.state, required this.saved});

  final RecorderState state;
  final ValueListenable<List<OfflineMap>> saved;

  @override
  Widget build(BuildContext context) {
    final fix = switch (state) {
      Recording(:final latestFix?) => latestFix,
      Recording(:final progress) ||
      Paused(:final progress) ||
      Interrupted(:final progress) => progress.lastFix,
      Idle() => null,
    };
    if (fix == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: saved,
      builder: (context, areas, _) {
        final inside = areas.any(
          (area) =>
              area.complete && covers(area.area, fix.latitude, fix.longitude),
        );
        if (!inside) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                Icons.offline_pin_outlined,
                size: 18,
                color: scheme.tertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Offline map saved for this area',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// On an expedition, the position as coordinates, on demand: to tell
/// someone where you are, or to check a map. Says when it is not live.
class Coordinates extends StatefulWidget {
  const Coordinates({super.key, required this.state, required this.now});

  final RecorderState state;
  final DateTime now;

  @override
  State<Coordinates> createState() => _CoordinatesState();
}

class _CoordinatesState extends State<Coordinates> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final (fix, live) = switch (widget.state) {
      Recording(
        journey: JourneyRow(mode: JourneyMode.expedition),
        :final latestFix?,
        :final latestFixArrivedAt?,
      ) =>
        (latestFix, widget.now.difference(latestFixArrivedAt) <= quietAfter),
      Recording(
        journey: JourneyRow(mode: JourneyMode.expedition),
        :final progress,
      ) ||
      Paused(
        journey: JourneyRow(mode: JourneyMode.expedition),
        :final progress,
      ) ||
      Interrupted(
        journey: JourneyRow(mode: JourneyMode.expedition),
        :final progress,
      ) => (progress.lastFix, false),
      _ => (null, false),
    };
    if (fix == null) return const SizedBox.shrink();
    if (!_shown) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _shown = true),
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('Show coordinates'),
        ),
      );
    }
    final text = coordinatesText(fix.latitude, fix.longitude);
    final accuracy = fix.accuracy;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _shown = false),
            child: Text(
              [
                if (!live) 'Last known:',
                text,
                if (accuracy != null) '±${accuracy.round()} m',
                // As the GPS reports it; GPS height is rougher than position.
                if (fix.altitude case final altitude?)
                  '· altitude ${altitude.round()} m'
                      '${switch (fix.altitudeAccuracy) {
                        final vertical? => ' ±${vertical.round()} m',
                        null => '',
                      }}',
              ].join(' '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: live ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text:
                    '${fix.latitude.toStringAsFixed(5)}, '
                    '${fix.longitude.toStringAsFixed(5)}',
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Coordinates copied')),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 20),
          tooltip: 'Copy coordinates',
        ),
      ],
    );
  }
}
