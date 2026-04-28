import 'dart:async';

import 'package:flutter/material.dart';

import '../journey/journey.dart';
import '../recording/location_source.dart';
import '../recording/recorder.dart';
import '../recording/track_policy.dart';
import 'figure.dart';
import 'format.dart';
import 'system_access.dart';
import 'theme.dart';

/// Seconds without a fix before the screen says so.
const _quietAfter = Duration(seconds: 15);

/// Seconds after starting without any fix before the screen says so.
const _noFixAfter = Duration(seconds: 30);

/// One journey at a time: its numbers, one main action, and plain words
/// about anything that is wrong. The map takes the centre in M1.
class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.recorder,
    required this.location,
    required this.system,
    required this.mapBuilder,
    this.historyBuilder,
    this.clock = _utcNow,
  });

  final Recorder recorder;
  final LocationSource location;
  final SystemAccess system;

  /// Builds the map behind the panel; injected so tests need no platform map.
  final Widget Function(RecorderState state, DateTime now) mapBuilder;

  /// Builds the list of past journeys, opened from the idle screen.
  final WidgetBuilder? historyBuilder;
  final DateTime Function() clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with WidgetsBindingObserver {
  late RecorderState _state = widget.recorder.state;
  late final StreamSubscription<RecorderState> _changes;
  Timer? _ticker;
  bool _busy = false;

  /// Android facts, refreshed on start and whenever the user comes back
  /// (they may have changed a setting meanwhile).
  bool? _notificationsShown;
  bool _restricted = false;
  List<LastExit> _exits = const [];

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
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshSystem());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_changes.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshSystem());
  }

  Future<void> _refreshSystem() async {
    final system = widget.system;
    final shown = await system.notificationsEnabled();
    final restricted = await system.isBackgroundRestricted();
    final exits = await system.recentExits();
    if (!mounted) return;
    setState(() {
      _notificationsShown = shown;
      _restricted = restricted;
      _exits = exits;
    });
  }

  /// Asks to show the recording notification before recording starts, at
  /// most as often as Android allows. A refusal does not stop recording.
  Future<void> _askForNotifications() async {
    if (_notificationsShown ?? false) return;
    final shown = await widget.system.requestNotifications();
    if (mounted) setState(() => _notificationsShown = shown);
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
      await _askForNotifications();
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
          'Journey saved · ${kilometres(last.meters)} · '
          '${clockTime(last.elapsedAt(widget.clock()))}',
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: widget.mapBuilder(state, now)),
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: _Header(state: state),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The panel holds everything that is not the map. It scrolls rather
          // than overflow when the text is large.
          Material(
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      switch (state) {
                        Idle() => const _Welcome(),
                        Recording(:final progress) ||
                        Paused(:final progress) ||
                        Interrupted(
                          :final progress,
                        ) => _Readout(progress: progress, now: now),
                      },
                      const SizedBox(height: 12),
                      _StatusLine(
                        state: state,
                        now: now,
                        exits: _exits,
                        onOpenLocationSettings: () => widget.location
                            .openSettingsFor(LocationAccess.serviceOff),
                        onOpenAppSettings: widget.system.openAppSettings,
                      ),
                      _SystemNotes(
                        state: state,
                        restricted: _restricted,
                        notificationsShown: _notificationsShown,
                        onOpenAppSettings: widget.system.openAppSettings,
                      ),
                      const SizedBox(height: 12),
                      if (_refused case final problem?)
                        _AccessProblem(
                          problem: problem,
                          onRetry: _retry == null
                              ? null
                              : () => _askFor(_retry!),
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
        ],
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
        if (widget.historyBuilder case final history?) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: history)),
            icon: const Icon(Icons.history),
            label: const Text('Past journeys'),
          ),
        ],
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
        'Recording · ${modeName(journey.mode)}',
        scheme.primary,
      ),
      Paused(:final journey) => (
        'Paused · ${modeName(journey.mode)}',
        scheme.onSurfaceVariant,
      ),
      Interrupted(:final journey) => (
        'Stopped · ${modeName(journey.mode)}',
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
        Text('Where to?', style: text.headlineMedium),
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
    return Row(
      children: [
        Expanded(
          child: Figure(
            value: clockTime(progress.elapsedAt(now)),
            label: 'Time',
          ),
        ),
        Expanded(
          child: Figure(value: kilometres(progress.meters), label: 'Distance'),
        ),
        Expanded(
          child: Figure(value: clockTime(progress.movingTime), label: 'Moving'),
        ),
      ],
    );
  }
}

typedef _Action = ({String label, VoidCallback onPressed});

/// One line about the GPS, saving or an interruption, in plain words, with
/// at most one action. Amber when something needs attention.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.state,
    required this.now,
    required this.exits,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  final RecorderState state;
  final DateTime now;

  /// Why recent processes ended, newest first, as Android recorded it.
  final List<LastExit> exits;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final (message, needsAttention, action) = switch (state) {
      Idle() => (null, false, null),
      final Recording recording => _recordingStatus(recording),
      Paused() => (
        'Paused. Nothing is recorded until you resume.',
        false,
        null,
      ),
      Interrupted(:final stoppedAt) => _interruption(context, stoppedAt),
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
        if (action != null)
          TextButton(onPressed: action.onPressed, child: Text(action.label)),
      ],
    );
  }

  (String, bool, _Action?) _recordingStatus(Recording state) {
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
        (label: 'Turn on location', onPressed: onOpenLocationSettings),
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
      // A start that fails inside the platform never reports an error, so
      // waiting too long is itself the signal (D-017).
      final since = state.progress.openSince;
      final waited = since == null ? Duration.zero : now.difference(since);
      if (waited > _noFixAfter) {
        return (
          'No GPS fix yet after ${age(waited)}. Fixes take longer indoors; '
              'check that location is on.',
          true,
          null,
        );
      }
      return ('Waiting for GPS…', false, null);
    }
    final quiet = now.difference(arrived);
    if (quiet > _quietAfter) {
      return ('No GPS fix for ${age(quiet)}', true, null);
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

  /// Names the real cause when Android recorded one, and offers battery
  /// settings only when battery management may be to blame.
  (String, bool, _Action?) _interruption(
    BuildContext context,
    DateTime stoppedAt,
  ) {
    final time = timeOfDay(context, stoppedAt);
    // The process that ended the recording is the first to exit after the
    // last saved fix; later exits (an update, a crash days later) are not
    // the cause. The fix carries GPS time, so allow some clock skew.
    final candidates = [
      for (final exit in exits)
        if (!exit.at.isBefore(stoppedAt.subtract(const Duration(minutes: 2))))
          exit,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final cause = candidates.firstOrNull?.cause;
    const lost = 'so nothing after that was recorded.';
    final battery = (label: 'Battery settings', onPressed: onOpenAppSettings);
    return switch (cause) {
      ExitCause.user => (
        'Recording stopped at $time because Tripping was stopped from Active '
            'apps or Settings, $lost',
        true,
        null,
      ),
      ExitCause.swiped => (
        'Recording stopped at $time because Tripping was swiped away from '
            'recent apps, $lost',
        true,
        null,
      ),
      ExitCause.crash => (
        'Recording stopped at $time because Tripping crashed, $lost',
        true,
        null,
      ),
      ExitCause.permission => (
        'Recording stopped at $time because location permission was turned '
            'off, $lost',
        true,
        null,
      ),
      ExitCause.update => (
        'Recording stopped at $time because Tripping was updated, $lost',
        true,
        null,
      ),
      ExitCause.memory => (
        'Recording stopped at $time: Android closed Tripping to free memory, '
            '$lost',
        true,
        battery,
      ),
      ExitCause.system || null => (
        'Recording stopped at $time. The phone closed Tripping, $lost If '
            'this keeps happening, set Tripping’s battery use to Unrestricted.',
        true,
        battery,
      ),
    };
  }
}

/// Android settings that silently undermine recording, stated up front.
class _SystemNotes extends StatelessWidget {
  const _SystemNotes({
    required this.state,
    required this.restricted,
    required this.notificationsShown,
    required this.onOpenAppSettings,
  });

  final RecorderState state;
  final bool restricted;
  final bool? notificationsShown;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final notes = [
      if (restricted)
        'Battery use for Tripping is set to Restricted, so recording stops '
            'when you leave the app.',
      if (state is Recording && notificationsShown == false)
        'Recording continues, but Android isn’t showing its notification. '
            'Allow notifications for Tripping to see it.',
    ];
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                note,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: warningColor(context)),
              ),
            ),
          TextButton(
            onPressed: onOpenAppSettings,
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
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
