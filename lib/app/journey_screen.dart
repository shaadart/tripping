import 'package:flutter/material.dart';

import '../history/journey_history.dart';
import '../journey/journey.dart';
import '../history/elevation_profile.dart';
import 'elevation_chart.dart';
import 'figure.dart';
import '../journey/journey_store.dart';
import '../map/track_geometry.dart';
import 'format.dart';
import 'components.dart';
import 'tokens.dart';
import '../map/map_symbols.dart';

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
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
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
          SheetSurface(
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.lg,
                    Space.gutter,
                    Space.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            journey.mode == JourneyMode.road
                                ? Icons.directions_car_outlined
                                : Icons.hiking,
                            size: 20,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Text(
                              [
                                modeName(journey.mode),
                                if (journey.endedAt case final ended?)
                                  'ended ${timeOfDay(context, ended)}',
                              ].join(' · '),
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                      Row(
                        children: [
                          Expanded(
                            child: Figure(
                              value: kilometres(past.meters),
                              label: 'Distance',
                            ),
                          ),
                          Expanded(
                            child: Figure(
                              value: clockTime(past.recordedTime),
                              label: 'Time',
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
                      if (parts > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.more_horiz_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Text(
                                  'Recorded in $parts parts. Nothing is known '
                                  'between them, so they are not joined or '
                                  'counted.',
                                  style: text.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                        future: _elevation,
                        builder: (context, snapshot) => switch (snapshot.data) {
                          final profile? => Padding(
                            padding: const EdgeInsets.only(top: Space.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Climb ${climbText(profile.climb)} · '
                                  'Descent ${climbText(profile.descent)}',
                                  style: text.bodyLarge,
                                ),
                                const SizedBox(height: Space.sm),
                                ElevationChart(profile: profile),
                              ],
                            ),
                          ),
                          null => const SizedBox.shrink(),
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
/// got there: the pin as on the map, and a mark that says it at a glance.
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
      padding: const EdgeInsets.only(top: Space.lg),
      child: Row(
        children: [
          const SizedBox(
            width: 40,
            child: MapSymbolGlyph(MapSymbol.destination),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To ${route.destination}',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  switch ((route.kind, meters)) {
                    (RouteKind.road, final meters?) =>
                      'Planned ${kilometres(meters)} ${wayWords(mode)}',
                    (RouteKind.straight, final meters?) =>
                      '${kilometres(meters)} in a straight line, '
                          '${notAWay(mode)}',
                    _ => 'No way was planned',
                  },
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Space.xs),
                _Badge(
                  label: there ? 'Reached' : 'Not reached',
                  icon: there ? Icons.check_rounded : Icons.remove_rounded,
                  colour: there ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short verdict in a tinted pill.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.icon, required this.colour});
  final String label;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: colour.withValues(alpha: .12),
      borderRadius: Corner.smallRadius,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(
              label,
              // The colour is in the tint and the icon; the word stays ink,
              // which reads on any tint (E-060).
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The journey's waypoints, numbered and drawn as on the map.
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
        const SizedBox(height: Space.lg),
        Semantics(
          header: true,
          child: Text(
            'Waypoints',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        for (final (i, waypoint) in waypoints.indexed)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  child: MapSymbolGlyph(
                    waypoint.kind == WaypointKind.marked
                        ? MapSymbol.marked
                        : MapSymbol.planned,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        waypoint.name ??
                            'Waypoint ${waypointLabel(waypoint, i)}',
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
