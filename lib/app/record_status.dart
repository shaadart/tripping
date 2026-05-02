import 'package:flutter/material.dart';
import '../recording/location_source.dart';
import '../recording/recorder.dart';
import '../recording/track_policy.dart';
import 'components.dart';
import 'format.dart';
import 'system_access.dart';
import 'tokens.dart';

/// Seconds without a fix before the screen says so.
const quietAfter = Duration(seconds: 15);

/// Seconds after starting without any fix before the screen says so.
const noFixAfter = Duration(seconds: 30);

typedef StatusAction = ({String label, VoidCallback onPressed});

/// One line about the GPS, saving or an interruption, in plain words, with
/// at most one action. Amber when something needs attention.
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.state,
    required this.now,
    required this.exits,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
    this.compact = false,
  });

  final bool compact;
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
        'Paused. Recording and group updates are stopped until you resume.',
        false,
        null,
      ),
      Interrupted(:final stoppedAt) => _interruption(context, stoppedAt),
    };
    if (message == null ||
        (compact &&
            !needsAttention &&
            state is Recording &&
            message.startsWith('GPS ±'))) {
      return const SizedBox.shrink();
    }
    if (needsAttention) {
      final current = state;
      return StatusNote(
        message,
        tone: current is Recording && current.saveError != null
            ? NoteTone.error
            : NoteTone.warning,
        actionLabel: action?.label,
        onAction: action?.onPressed,
      );
    }
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  (String, bool, StatusAction?) _recordingStatus(Recording state) {
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
      if (waited > noFixAfter) {
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
    if (quiet > quietAfter) {
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
  (String, bool, StatusAction?) _interruption(
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
class SystemNotes extends StatelessWidget {
  const SystemNotes({
    super.key,
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
      padding: const EdgeInsets.only(top: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, note) in notes.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : Space.sm),
              child: StatusNote(
                note,
                actionLabel: i == notes.length - 1 ? 'Open settings' : null,
                onAction: onOpenAppSettings,
              ),
            ),
        ],
      ),
    );
  }
}

class AccessProblem extends StatelessWidget {
  const AccessProblem({
    super.key,
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
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: StatusNote(
        message,
        actionLabel: action,
        onAction: retries ? onRetry : onOpenSettings,
      ),
    );
  }
}
