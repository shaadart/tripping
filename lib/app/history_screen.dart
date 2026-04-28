import 'dart:math';

import 'package:flutter/material.dart';

import '../history/journey_history.dart';
import '../journey/journey.dart';
import 'format.dart';
import 'journey_screen.dart';

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
  final Widget Function(List<List<Fix>>? track) trackMapBuilder;

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
          if (journeys.isEmpty) {
            return const _Message(
              'No journeys yet. Journeys you end are kept here, on this '
              'phone.',
            );
          }
          return ListView.builder(
            itemCount: journeys.length,
            itemBuilder: (context, i) => _JourneyTile(
              past: journeys[i],
              onTap: () => _open(journeys[i]),
            ),
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
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}

class _JourneyTile extends StatelessWidget {
  const _JourneyTile({required this.past, required this.onTap});

  final PastJourney past;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(
          painter: OutlinePainter(past.outline, color: scheme.primary),
        ),
      ),
      title: Text(dayAndTime(context, past.journey.createdAt)),
      subtitle: Text(
        '${modeName(past.journey.mode)} · ${kilometres(past.meters)} · '
        '${clockTime(past.recordedTime)}',
      ),
    );
  }
}

/// Paints a journey's outline to fit, north up, without a map: cheap enough
/// for long lists.
class OutlinePainter extends CustomPainter {
  OutlinePainter(this.outline, {required this.color});

  final List<List<OutlinePoint>> outline;
  final Color color;

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
    const inset = 8.0;
    final scale = span == 0 ? 0.0 : (size.shortestSide - 2 * inset) / span;
    final centre = size.center(Offset.zero);
    Offset at(OutlinePoint p) =>
        centre +
        Offset(
          (p.longitude - (west + east) / 2) * squeeze * scale,
          ((south + north) / 2 - p.latitude) * scale,
        );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final segment in outline) {
      if (segment.length == 1) {
        canvas.drawCircle(
          at(segment.single),
          2,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path();
      for (final (i, p) in segment.indexed) {
        final o = at(p);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(OutlinePainter old) =>
      !identical(old.outline, outline) || old.color != color;
}
