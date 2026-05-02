import 'package:flutter/material.dart';
import '../journey/geo.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../places/place.dart';
import '../routing/route_progress.dart';
import '../routing/router.dart';
import '../recording/course.dart';
import 'format.dart';
import 'record_status.dart';

/// Before a trip: where it will go, or a way to choose.
class NextDestination extends StatelessWidget {
  const NextDestination({
    super.key,
    required this.pending,
    required this.onSearch,
    required this.onClear,
  });

  final Place? pending;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final pending = this.pending;
    if (pending == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Search a place'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DestinationCard(
        title: 'To ${pending.name}',
        subtitle: pending.detail ?? 'The way is planned once you start.',
        onSearch: onSearch,
        onClear: onClear,
      ),
    );
  }
}

/// During a trip: where it is going and how far, in plain words. A straight
/// line says it is one.
class DestinationLine extends StatelessWidget {
  const DestinationLine({
    super.key,
    required this.mode,
    required this.route,
    required this.why,
    required this.planning,
    required this.progress,
    required this.now,
    required this.here,
    required this.heading,
    required this.onSearch,
    required this.onClear,
    required this.onRetry,
  });

  final JourneyMode mode;
  final RouteRow? route;
  final RouteError? why;
  final bool planning;

  /// How far along the way, while recording with a live fix.
  final RouteProgress? progress;
  final DateTime now;

  /// On an expedition, the live fix to tell the destination's direction
  /// from.
  final Fix? here;

  /// The direction of travel, when known (see [Course]).
  final double? heading;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final route = this.route;
    if (route == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Set a destination'),
        ),
      );
    }
    final progress = this.progress;
    final meters = progress?.metersLeft ?? route.meters ?? 0;
    final seconds = progress == null ? route.seconds : progress.secondsLeft;
    final why = this.why;
    final (subtitle, retry) = switch ((route.kind, progress)) {
      (_, RouteProgress(arrived: true)) => ('You have arrived.', false),
      (RouteKind.road, RouteProgress(offRoute: true)) => (
        [
          'Off the route · ${kilometres(meters)} away in a straight line.',
          if (planning) 'Finding a new way…' else if (why != null) why.message,
        ].join(' '),
        !planning && why != null,
      ),
      _ when planning && route.kind == null => ('Planning the way…', false),
      (null, _) => ('The way is planned at the first GPS fix.', false),
      (RouteKind.road, null) => (
        '${kilometres(meters)} ${wayWords(mode)}'
            '${seconds == null ? '' : ' · ${_roughly(seconds)}'}',
        false,
      ),
      (RouteKind.road, _) => (
        '${kilometres(meters)} to go ${wayWords(mode)}'
            '${seconds == null ? '' : ' · ${_roughly(seconds)}, arriving '
                      'around ${_clock(context, seconds)}'}',
        false,
      ),
      (RouteKind.straight, _) => (
        '${kilometres(meters)} in a straight line, ${notAWay(mode)}. '
            '${planning ? 'Looking for a way…' : why?.message ?? 'No way was found.'}',
        !planning,
      ),
    };
    final compass = _compass(route);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DestinationCard(
        title: 'To ${route.destination}',
        subtitle: compass == null ? subtitle : '$subtitle\n$compass',
        onSearch: onSearch,
        onClear: onClear,
        action: retry ? (label: 'Try again', onPressed: onRetry) : null,
      ),
    );
  }

  /// "1.24 km NW (312°) in a straight line · ahead left": the direction
  /// as the crow flies, and, while moving, where that is from the way the
  /// walker is going. Off-trail, this is what finds the way.
  String? _compass(RouteRow route) {
    final here = this.here;
    if (here == null || (progress?.arrived ?? false)) return null;
    final bearing = bearingBetween(
      here.latitude,
      here.longitude,
      route.latitude,
      route.longitude,
    );
    final meters = metersBetween(
      here.latitude,
      here.longitude,
      route.latitude,
      route.longitude,
    );
    final heading = this.heading;
    return [
      '${kilometres(meters)} ${compassPoint(bearing)} '
          '(${bearing.round() % 360}°) in a straight line',
      if (heading != null) relativeDirection(bearing, heading),
    ].join(' · ');
  }

  /// The time of day [seconds] from [now]: an estimate, said as one.
  String _clock(BuildContext context, double seconds) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(
          now.add(Duration(seconds: seconds.round())).toLocal(),
        ),
      );

  /// "about 25 min", "about 2 h 10 min": a service's estimate, not a
  /// promise.
  static String _roughly(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return 'about $minutes min';
    return 'about ${minutes ~/ 60} h ${minutes % 60} min';
  }
}

class DestinationCard extends StatelessWidget {
  const DestinationCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSearch,
    required this.onClear,
    this.action,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final StatusAction? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.flag_circle_outlined, color: scheme.secondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              Text(
                subtitle,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action case final action?)
                TextButton(
                  onPressed: action.onPressed,
                  child: Text(action.label),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onSearch,
          icon: const Icon(Icons.edit_location_alt_outlined),
          tooltip: 'Change destination',
        ),
        IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.close),
          tooltip: 'No destination',
        ),
      ],
    );
  }
}
