import 'package:flutter/material.dart';

import '../history/journey_history.dart';
import '../journey/journey.dart';
import 'figure.dart';
import 'format.dart';

/// One past journey: its track on the map and its numbers. Pops `true` when
/// the journey was deleted.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({
    super.key,
    required this.past,
    required this.history,
    required this.trackMapBuilder,
    this.onExport,
  });

  final PastJourney past;
  final JourneyHistory history;

  /// Builds the map; the track is null while it loads.
  final Widget Function(List<List<Fix>>? track) trackMapBuilder;

  /// Hands the journey to other apps as GPX.
  final Future<void> Function(PastJourney past)? onExport;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late final Future<List<List<Fix>>> _track = widget.history.trackOf(
    widget.past.journey.id,
  );

  Future<void> _export(Future<void> Function(PastJourney) export) async {
    try {
      await export(widget.past);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't export: $error")));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this journey?'),
        content: const Text(
          'Its track is removed from this phone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await widget.history.delete(widget.past.journey.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final past = widget.past;
    final journey = past.journey;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final parts = past.outline.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(dayAndTime(context, journey.createdAt)),
        actions: [
          if (widget.onExport case final export?)
            IconButton(
              onPressed: () => _export(export),
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Export GPX',
            ),
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete journey',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder(
              future: _track,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text("Couldn't read the track: ${snapshot.error}"),
                  );
                }
                // Built at once, so the map loads while the track does.
                return widget.trackMapBuilder(snapshot.data);
              },
            ),
          ),
          Material(
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Figure(
                            value: clockTime(past.recordedTime),
                            label: 'Time',
                          ),
                        ),
                        Expanded(
                          child: Figure(
                            value: kilometres(past.meters),
                            label: 'Distance',
                          ),
                        ),
                        Expanded(
                          child: Figure(
                            value: clockTime(past.movingTime),
                            label: 'Moving',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      [
                        modeName(journey.mode),
                        if (journey.endedAt case final ended?)
                          'ended ${timeOfDay(context, ended)}',
                      ].join(' · '),
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (parts > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Recorded in $parts parts. Nothing is known between '
                          'them, so they are not joined or counted.',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
