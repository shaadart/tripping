import 'dart:math';

import 'package:flutter/material.dart';

import '../history/journey_history.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import 'components.dart';
import 'format.dart';
import 'journey_screen.dart';
import 'map_ground.dart';
import 'tokens.dart';

/// Every ended journey on this phone, newest first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.history,
    required this.trackMapBuilder,
    this.onExport,
  });

  final JourneyHistory history;

  /// Hands a journey to other apps as GPX.
  final Future<void> Function(PastJourney past)? onExport;

  /// Builds the map of a past journey; injected so tests need no platform
  /// map.
  final Widget Function(
    List<List<Fix>>? track,
    List<WaypointRow> waypoints,
    RouteRow? route,
  )
  trackMapBuilder;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<PastJourney>> _journeys = widget.history.load();

  Future<void> _open(PastJourney past) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JourneyScreen(
          past: past,
          history: widget.history,
          trackMapBuilder: widget.trackMapBuilder,
          onExport: widget.onExport,
        ),
      ),
    );
    if (deleted ?? false) {
      final reloaded = widget.history.load();
      setState(() {
        _journeys = reloaded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past journeys')),
      body: FutureBuilder(
        future: _journeys,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message("Couldn't read your journeys: ${snapshot.error}");
          }
          final journeys = snapshot.data;
          if (journeys == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (journeys.isEmpty) return const _Empty();
          final rows = <Widget>[_Totals(journeys)];
          String? month;
          final localizations = MaterialLocalizations.of(context);
          for (final past in journeys) {
            final heading = localizations.formatMonthYear(
              past.journey.createdAt.toLocal(),
            );
            if (heading != month) {
              month = heading;
              rows.add(_MonthHeading(heading));
            }
            rows.add(_JourneyCard(past: past, onTap: () => _open(past)));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              Space.xxl,
            ),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
            itemBuilder: (_, i) => rows[i],
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xxl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}

/// Before any journey: an empty map with a faint way still to be walked.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final ground = MapGround.of(groundLook(context));
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: Corner.largeRadius,
              child: SizedBox(
                height: 180,
                width: double.infinity,
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: MapGroundPainter(ground),
                    foregroundPainter: _FirstWayPainter(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              'No journeys yet',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.xs),
            Text(
              'Journeys you end are kept here, on this phone.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FirstWayPainter extends CustomPainter {
  const _FirstWayPainter(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * .14, h * .78)
      ..cubicTo(w * .34, h * .9, w * .5, h * .3, w * .86, h * .26);
    final dash = Paint()
      ..color = ink.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 16) {
        canvas.drawPath(metric.extractPath(d, d + 6), dash);
      }
    }
    canvas.drawCircle(
      Offset(w * .14, h * .78),
      7,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_FirstWayPainter old) => old.ink != ink;
}

/// Everything kept here, added up: the distance first, the rest after.
class _Totals extends StatelessWidget {
  const _Totals(this.journeys);
  final List<PastJourney> journeys;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final meters = journeys.fold(0.0, (sum, p) => sum + p.meters);
    final time = journeys.fold(Duration.zero, (sum, p) => sum + p.recordedTime);
    final count = journeys.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Semantics(
        label:
            '${kilometres(meters)} in $count '
            '${count == 1 ? 'journey' : 'journeys'}, ${clockTime(time)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kilometres(meters),
              style: text.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              '$count ${count == 1 ? 'journey' : 'journeys'} · '
              '${clockTime(time)}',
              style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeading extends StatelessWidget {
  const _MonthHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// One journey: its shape on a scrap of map, when, how far and how long.
class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.past, required this.onTap});

  final PastJourney past;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ground = MapGround.of(groundLook(context));
    final journey = past.journey;
    final when = dayAndTime(context, journey.createdAt);
    final summary =
        '${modeName(journey.mode)} · ${kilometres(past.meters)} · '
        '${clockTime(past.recordedTime)}';
    return Semantics(
      button: true,
      label: '$when. $summary',
      excludeSemantics: true,
      child: MapChrome(
        key: ValueKey('journey-${journey.id}'),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: Corner.smallRadius,
                  child: SizedBox.square(
                    dimension: 88,
                    child: CustomPaint(
                      painter: MapGroundPainter(ground),
                      foregroundPainter: OutlinePainter(
                        past.outline,
                        color: scheme.primary,
                        casing: ground.land,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        when,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        kilometres(past.meters),
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            journey.mode == JourneyMode.road
                                ? Icons.directions_car_outlined
                                : Icons.hiking,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: Space.xs),
                          Flexible(
                            child: Text(
                              '${modeName(journey.mode)} · '
                              '${clockTime(past.recordedTime)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a journey's outline to fit, north up, without a map: cheap enough
/// for long lists. With a [casing], the line sits on the ground the way the
/// map draws it, with a start ring and a finish square.
class OutlinePainter extends CustomPainter {
  OutlinePainter(this.outline, {required this.color, this.casing});

  final List<List<OutlinePoint>> outline;
  final Color color;
  final Color? casing;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [for (final segment in outline) ...segment];
    if (points.isEmpty) return;
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      south = min(south, p.latitude);
      north = max(north, p.latitude);
      west = min(west, p.longitude);
      east = max(east, p.longitude);
    }
    // Degrees of longitude shrink away from the equator.
    final squeeze = cos((south + north) / 2 * pi / 180);
    final span = max((east - west) * squeeze, north - south);
    final inset = casing == null ? 8.0 : 14.0;
    final scale = span == 0 ? 0.0 : (size.shortestSide - 2 * inset) / span;
    final centre = size.center(Offset.zero);
    Offset at(OutlinePoint p) =>
        centre +
        Offset(
          (p.longitude - (west + east) / 2) * squeeze * scale,
          ((south + north) / 2 - p.latitude) * scale,
        );

    Paint stroke(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final paths = <Path>[];
    for (final segment in outline) {
      if (segment.length == 1) {
        canvas.drawCircle(at(segment.single), 2, Paint()..color = color);
        continue;
      }
      final path = Path();
      for (final (i, p) in segment.indexed) {
        final o = at(p);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      paths.add(path);
    }
    final edge = casing;
    if (edge != null) {
      for (final path in paths) {
        canvas.drawPath(path, stroke(edge, 6));
      }
    }
    for (final path in paths) {
      canvas.drawPath(path, stroke(color, edge == null ? 2.5 : 3.5));
    }
    if (edge == null) return;
    final start = at(points.first), finish = at(points.last);
    canvas.drawCircle(start, 5, Paint()..color = edge);
    canvas.drawCircle(start, 4, stroke(color, 2.5));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: finish, width: 8, height: 8),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(OutlinePainter old) =>
      !identical(old.outline, outline) ||
      old.color != color ||
      old.casing != casing;
}
