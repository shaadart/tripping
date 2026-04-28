import 'dart:async';

import 'package:flutter/material.dart';

import '../journey/journey.dart';
import '../recording/location_source.dart';
import '../recording/recorder.dart';
import '../recording/track_policy.dart';
import 'theme.dart';

/// Seconds without a fix before the screen says so.
const _quietAfter = Duration(seconds: 15);

/// One journey at a time: its numbers, one main action, and plain words
/// about anything that is wrong. The map takes the centre in M1.
class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.recorder,
    required this.location,
    this.clock = _utcNow,
  });

  final Recorder recorder;
  final LocationSource location;
  final DateTime Function() clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late RecorderState _state = widget.recorder.state;
  late final StreamSubscription<RecorderState> _changes;
  Timer? _ticker;
  bool _busy = false;

  /// Why the last start or resume could not go ahead, and how to retry it.
  LocationAccess? _refused;
  Future<LocationAccess> Function()? _retry;

  @override
  void initState() {
    super.initState();
    _changes = widget.recorder.changes.listen((state) {
      setState(() => _state = state);
      _syncTicker();
    });
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_changes.cancel());
    super.dispose();
  }

  /// Ticks once a second only while recording, for the clock and the age of
  /// the last fix.
  void _syncTicker() {
    if (_state is Recording) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _askFor(Future<LocationAccess> Function() command) async {
    setState(() {
      _busy = true;
      _refused = null;
    });
    try {
      final access = await command();
      if (!mounted) return;
      setState(() {
        _refused = access == LocationAccess.granted ? null : access;
        _retry = command;
      });
    } catch (error) {
      _tell('Something went wrong: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() async {
    try {
      await widget.recorder.pause();
    } catch (error) {
      _tell('Could not pause: $error. Still recording.');
    }
  }

  Future<void> _end() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this journey?'),
        content: const Text('It stays saved on this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End journey'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final last = await widget.recorder.end();
      if (last != null) {
        _tell(
          'Journey saved · ${_kilometres(last.meters)} · '
          '${_duration(last.elapsedAt(widget.clock()))}',
        );
      }
    } catch (error) {
      _tell('Could not end the journey: $error');
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final state = _state;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight - 40),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(state: state),
                    const Spacer(),
                    switch (state) {
                      Idle() => const _Welcome(),
                      Recording(:final progress) ||
                      Paused(:final progress) ||
                      Interrupted(
                        :final progress,
                      ) => _Readout(progress: progress, now: now),
                    },
                    const SizedBox(height: 24),
                    _StatusLine(
                      state: state,
                      now: now,
                      onOpenSettings: widget.location.openSettingsFor,
                    ),
                    const Spacer(),
                    if (_refused case final problem?)
                      _AccessProblem(
                        problem: problem,
                        onRetry: _retry == null ? null : () => _askFor(_retry!),
                        onOpenSettings: () =>
                            widget.location.openSettingsFor(problem),
                      ),
                    ..._actions(state),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(RecorderState state) {
    final recorder = widget.recorder;
    final enabled = !_busy;
    return switch (state) {
      Idle() => [
        FilledButton.icon(
          onPressed: enabled
              ? () => _askFor(() => recorder.start(JourneyMode.road))
              : null,
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('Road journey'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: enabled
              ? () => _askFor(() => recorder.start(JourneyMode.expedition))
              : null,
          icon: const Icon(Icons.hiking),
          label: const Text('Expedition'),
        ),
      ],
      Recording() => [
        FilledButton.icon(
          onPressed: enabled ? _pause : null,
          icon: const Icon(Icons.pause),
          label: const Text('Pause'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: enabled ? _end : null,
          child: const Text('End journey'),
        ),
      ],
      Paused() || Interrupted() => [
        FilledButton.icon(
          onPressed: enabled ? () => _askFor(recorder.resume) : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: enabled ? _end : null,
          child: const Text('End journey'),
        ),
      ],
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final RecorderState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state) {
      Idle() => ('Tripping', scheme.onSurface),
      Recording(:final journey) => (
        'Recording · ${_modeName(journey.mode)}',
        scheme.primary,
      ),
      Paused(:final journey) => (
        'Paused · ${_modeName(journey.mode)}',
        scheme.onSurfaceVariant,
      ),
      Interrupted(:final journey) => (
        'Stopped · ${_modeName(journey.mode)}',
        warningColor(context),
      ),
    };
    return Row(
      children: [
        if (state is Recording) ...[
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where to?', style: text.displaySmall),
        const SizedBox(height: 12),
        Text(
          'Record a road journey or an expedition. Everything stays on this '
          'phone, and no internet is needed.',
          style: text.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.progress, required this.now});

  final Progress progress;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const tabular = [FontFeature.tabularFigures()];
    final elapsed = _duration(progress.elapsedAt(now));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          elapsed,
          semanticsLabel: 'Recording time $elapsed',
          style: text.displayLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: tabular,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _Figure(
                value: _kilometres(progress.meters),
                label: 'Distance',
              ),
            ),
            Expanded(
              child: _Figure(
                value: _duration(progress.movingTime),
                label: 'Moving',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: text.headlineMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One line about the GPS and saving, in plain words. Amber when something
/// needs attention.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.state,
    required this.now,
    required this.onOpenSettings,
  });

  final RecorderState state;
  final DateTime now;
  final Future<void> Function(LocationAccess problem) onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final (message, needsAttention, fixable) = switch (state) {
      Idle() => (null, false, null),
      final Recording recording => _recordingStatus(recording),
      Paused() => (
        'Paused. Nothing is recorded until you resume.',
        false,
        null,
      ),
      Interrupted(:final stoppedAt) => (
        'Recording stopped at ${_timeOfDay(context, stoppedAt)}. The phone '
            'closed Tripping, so nothing after that was recorded.',
        true,
        null,
      ),
    };
    if (message == null) return const SizedBox.shrink();
    final color = needsAttention
        ? warningColor(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
        ),
        if (fixable != null)
          TextButton(
            onPressed: () => onOpenSettings(fixable),
            child: const Text('Turn on location'),
          ),
      ],
    );
  }

  (String, bool, LocationAccess?) _recordingStatus(Recording state) {
    if (state.saveError != null) {
      return (
        'Can’t save to this phone. Positions are not being recorded.',
        true,
        null,
      );
    }
    final problem = state.locationProblem;
    if (problem is LocationUnavailable &&
        problem.reason == LocationAccess.serviceOff) {
      return (
        'Location is off. Still recording — turn it on to continue the track.',
        true,
        LocationAccess.serviceOff,
      );
    }
    if (problem != null) {
      return (
        'Location stopped. Still recording; the track resumes when it '
            'returns.',
        true,
        null,
      );
    }
    final fix = state.latestFix;
    final arrived = state.latestFixArrivedAt;
    if (fix == null || arrived == null) {
      return ('Waiting for GPS…', false, null);
    }
    final quiet = now.difference(arrived);
    if (quiet > _quietAfter) {
      return ('No GPS fix for ${_age(quiet)}', true, null);
    }
    final accuracy = fix.accuracy;
    final ceiling = TrackPolicy.of(state.journey.mode).maxAccuracy;
    if (accuracy == null) return ('GPS fix, accuracy unknown', false, null);
    if (accuracy > ceiling) {
      return (
        'Location approximate (±${accuracy.round()} m), not added to the '
            'track',
        true,
        null,
      );
    }
    return ('GPS ±${accuracy.round()} m', false, null);
  }
}

class _AccessProblem extends StatelessWidget {
  const _AccessProblem({
    required this.problem,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final LocationAccess problem;
  final VoidCallback? onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final (message, action, retries) = switch (problem) {
      LocationAccess.denied => (
        'Tripping needs your location to record a journey. It stays on this '
            'phone.',
        'Allow location',
        true,
      ),
      LocationAccess.deniedForever => (
        'Location is not allowed for Tripping. Allow it in Settings, then '
            'try again.',
        'Open settings',
        false,
      ),
      LocationAccess.approximate => (
        'Tripping only has approximate location, which is too coarse for a '
            'track. Turn on precise location in Settings.',
        'Open settings',
        false,
      ),
      LocationAccess.serviceOff => (
        'Location is turned off on this phone.',
        'Turn on location',
        false,
      ),
      LocationAccess.granted => ('', '', false),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: warningColor(context)),
          ),
          TextButton(
            onPressed: retries ? onRetry : onOpenSettings,
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

String _modeName(JourneyMode mode) => switch (mode) {
  JourneyMode.road => 'Road journey',
  JourneyMode.expedition => 'Expedition',
};

String _kilometres(double meters) => '${(meters / 1000).toStringAsFixed(2)} km';

String _duration(Duration duration) {
  final hours = duration.inHours;
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String _age(Duration age) {
  if (age.inSeconds < 60) return '${age.inSeconds} s';
  if (age.inMinutes < 60) return '${age.inMinutes} min';
  return '${age.inHours} h ${age.inMinutes % 60} min';
}

String _timeOfDay(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(time.toLocal()));
