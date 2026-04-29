import 'package:flutter/material.dart';

import '../history/journey_history.dart';
import '../journey/journey.dart';
import '../history/elevation_profile.dart';
import 'elevation_chart.dart';
import 'figure.dart';
import '../journey/journey_store.dart';
import '../map/track_geometry.dart';
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
  final Widget Function(
    List<List<Fix>>? track,
    List<WaypointRow> waypoints,
    RouteRow? route,
  )
  trackMapBuilder;

  /// Hands the journey to other apps as GPX.
  final Future<void> Function(PastJourney past)? onExport;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late final Future<ElevationProfile?> _elevation = widget.history.elevationOf(
    widget.past,
  );

  late final Future<(List<List<Fix>>, List<WaypointRow>, RouteRow?)> _loaded = (
    widget.history.trackOf(widget.past.journey.id),
    widget.history.waypointsOf(widget.past.journey.id),
    widget.history.routeOf(widget.past.journey.id),
  ).wait;

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
              future: _loaded,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text("Couldn't read the track: ${snapshot.error}"),
                  );
                }
                // Built at once, so the map loads while the track does.
                final (track, waypoints, route) =
                    snapshot.data ?? (null, const <WaypointRow>[], null);
                return widget.trackMapBuilder(track, waypoints, route);
              },
            ),
          ),
          Material(
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SingleChildScrollView(
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
                      FutureBuilder(
                        future: _elevation,
                        builder: (context, snapshot) => switch (snapshot.data) {
                          final profile? => Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Climb ${climbText(profile.climb)} · '
                                  'Descent ${climbText(profile.descent)}',
                                  style: text.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                ElevationChart(profile: profile),
                              ],
                            ),
                          ),
                          null => const SizedBox.shrink(),
                        },
                      ),
                      FutureBuilder(
                        future: _loaded,
                        builder: (context, snapshot) => switch (snapshot.data) {
                          (final track, _, final route?) => _Destination(
                            mode: journey.mode,
                            route: route,
                            track: track,
                          ),
                          _ => const SizedBox.shrink(),
                        },
                      ),
                      FutureBuilder(
                        future: _loaded,
                        builder: (context, snapshot) => _Waypoints(
                          waypoints: snapshot.data?.$2 ?? const [],
                        ),
                      ),
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
}

/// Where the journey was going, the way planned, and whether the track
/// got there.
class _Destination extends StatelessWidget {
  const _Destination({
    required this.mode,
    required this.route,
    required this.track,
  });

  final JourneyMode mode;
  final RouteRow route;
  final List<List<Fix>> track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final meters = route.meters;
    final there = reached(track, route.latitude, route.longitude);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_circle_outlined, size: 20, color: scheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('To ${route.destination}', style: text.bodyLarge),
                Text(
                  [
                    switch ((route.kind, meters)) {
                      (RouteKind.road, final meters?) =>
                        'Planned ${kilometres(meters)} ${wayWords(mode)}',
                      (RouteKind.straight, final meters?) =>
                        '${kilometres(meters)} in a straight line, '
                            '${notAWay(mode)}',
                      _ => 'No way was planned',
                    },
                    there ? 'Reached' : 'Not reached',
                  ].join(' · '),
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The journey's waypoints, numbered as on the map.
class _Waypoints extends StatelessWidget {
  const _Waypoints({required this.waypoints});

  final List<WaypointRow> waypoints;

  @override
  Widget build(BuildContext context) {
    if (waypoints.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('Waypoints', style: text.titleMedium),
        for (final (i, waypoint) in waypoints.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  waypoint.kind == WaypointKind.marked
                      ? Icons.flag
                      : Icons.outlined_flag,
                  size: 20,
                  color: waypoint.kind == WaypointKind.marked
                      ? scheme.tertiary
                      : scheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        waypoint.name ??
                            'Waypoint ${waypointLabel(waypoint, i)}',
                        style: text.bodyLarge,
                      ),
                      Text(
                        [
                          switch (waypoint.kind) {
                            WaypointKind.marked =>
                              'Marked ${timeOfDay(context, waypoint.fixTime ?? waypoint.createdAt)}',
                            WaypointKind.planned => 'Planned',
                          },
                          coordinatesText(
                            waypoint.latitude,
                            waypoint.longitude,
                          ),
                          if (waypoint.accuracy case final accuracy?)
                            '±${accuracy.round()} m',
                        ].join(' · '),
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (waypoint.note case final note?)
                        Text(note, style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
