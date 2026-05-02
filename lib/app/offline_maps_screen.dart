import 'dart:async';

import 'dart:math';

import 'package:flutter/material.dart';

import '../map/offline_area.dart';
import '../map/offline_maps.dart';
import 'components.dart';
import 'map_ground.dart';
import 'theme.dart';
import 'tokens.dart';

/// Builds a map that reports the area it shows whenever it comes to rest;
/// injected so tests need no platform map.
typedef AreaMapBuilder = Widget Function(ValueChanged<Area> onArea);

/// Areas kept for use without a connection: download them before a trip.
class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({
    super.key,
    required this.maps,
    required this.areaMapBuilder,
  });

  final OfflineMaps maps;
  final AreaMapBuilder areaMapBuilder;

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  late Future<List<OfflineMap>> _areas = widget.maps.list();

  /// Read once per visit; null without a connection.
  late final Future<String?> _newest = widget.maps.newestRelease();

  double? _updating;
  String? _updateError;
  StreamSubscription<double>? _update;

  @override
  void dispose() {
    // An update keeps going without this screen; only stop listening.
    _update?.cancel();
    super.dispose();
  }

  void _updateAll() {
    setState(() {
      _updating = 0;
      _updateError = null;
    });
    _update = widget.maps.updateAll().listen(
      (progress) => setState(() => _updating = progress),
      onError: (Object error) => setState(() {
        _updating = null;
        _updateError = '$error';
      }),
      onDone: () {
        if (!mounted) return;
        final failed = _updateError != null;
        setState(() => _updating = null);
        _reload();
        if (!failed) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Offline maps updated')));
        }
      },
    );
  }

  void _reload() {
    final next = widget.maps.list();
    setState(() {
      _areas = next;
    });
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AreaPicker(
          maps: widget.maps,
          areaMapBuilder: widget.areaMapBuilder,
        ),
      ),
    );
    if (!mounted) return;
    _reload();
    if (saved ?? false) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved for offline use')));
    }
  }

  Future<void> _delete(OfflineMap area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${area.name}?'),
        content: const Text(
          'Its map will no longer be on this phone. Journeys are not '
          'affected.',
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
    await widget.maps.delete(area.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline maps')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.lg,
          ),
          child: FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('Download an area'),
          ),
        ),
      ),
      body: FutureBuilder(
        future: _areas,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(
              "Couldn't read the offline maps: ${snapshot.error}",
            );
          }
          final areas = snapshot.data;
          if (areas == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (areas.isEmpty) {
            return const _Empty();
          }
          final bytes = areas.fold(0, (sum, a) => sum + a.bytes);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              Space.lg,
            ),
            children: [
              Semantics(
                label:
                    '${megabytes(bytes)} of maps in ${areas.length} '
                    '${areas.length == 1 ? 'area' : 'areas'} on this phone',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      megabytes(bytes),
                      style: text.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Text(
                      '${areas.length} '
                      '${areas.length == 1 ? 'area' : 'areas'} on this phone',
                      style: text.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FutureBuilder(
                future: _newest,
                builder: (context, snapshot) {
                  final newest = snapshot.data;
                  final stale = newest == null
                      ? 0
                      : areas.where((a) => !a.isCurrent(newest)).length;
                  if (stale == 0 && _updating == null) {
                    return const SizedBox.shrink();
                  }
                  return _UpdateBanner(
                    stale: stale,
                    progress: _updating,
                    error: _updateError,
                    onUpdate: _updateAll,
                  );
                },
              ),
              for (final area in areas)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: _AreaCard(
                    area: area,
                    detail: area.complete
                        ? '${megabytes(area.bytes)} · saved '
                              '${_day(context, area.savedAt)}'
                        : 'Incomplete (${(area.progress * 100).round()} %): '
                              'delete it and download again',
                    onDelete: () => _delete(area),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _day(BuildContext context, DateTime? at) => at == null
      ? '—'
      : MaterialLocalizations.of(context).formatMediumDate(at.toLocal());
}

/// Offers newer map data for saved areas, all at once.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.stale,
    required this.progress,
    required this.error,
    required this.onUpdate,
  });

  final int stale;
  final double? progress;
  final String? error;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final progress = this.progress;
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: MapChrome(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: scheme.primary),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Newer map data is available',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              '${stale == 1 ? 'One saved area uses' : '$stale saved areas use'} '
              'older map data. They still work offline; update them to add '
              'new areas. The old copies stay until the update has finished.',
              style: text.bodyMedium,
            ),
            if (error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: StatusNote(
                  '$error Nothing was changed.',
                  tone: NoteTone.error,
                ),
              ),
            const SizedBox(height: Space.md),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: Space.sm),
              Text('Updating… ${(progress * 100).round()} %'),
            ] else
              FilledButton.icon(
                onPressed: onUpdate,
                icon: const Icon(Icons.update),
                label: const Text('Update all'),
              ),
          ],
        ),
      ),
    );
  }
}

/// "4.2 MB": one decimal is plenty for a download.
String megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

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

/// No saved maps: a scrap of map with an empty frame waiting to be filled.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 180,
              width: double.infinity,
              child: _AreaScrap(area: null, complete: false, progress: 0),
            ),
            const SizedBox(height: Space.lg),
            Text(
              'No offline maps yet',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.xs),
            Text(
              'Download the areas of a trip while you have internet. They '
              'work without a connection, under your track, waypoints and '
              'position.',
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

/// One saved area: its own shape framed on a scrap of map, its name, size
/// and age, and a way to remove it.
class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.area,
    required this.detail,
    required this.onDelete,
  });

  final OfflineMap area;
  final String detail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return MapChrome(
      child: Padding(
        padding: const EdgeInsets.all(Space.sm),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 72,
              child: _AreaScrap(
                area: area.area,
                complete: area.complete,
                progress: area.progress,
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    area.name,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    detail,
                    style: text.bodyMedium?.copyWith(
                      color: area.complete
                          ? scheme.onSurfaceVariant
                          : warningColor(context),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete ${area.name}',
            ),
          ],
        ),
      ),
    );
  }
}

/// A scrap of map with the area drawn to its true proportions: solid and
/// ticked once saved, a ring filling up while it is not.
class _AreaScrap extends StatelessWidget {
  const _AreaScrap({
    required this.area,
    required this.complete,
    required this.progress,
  });

  final Area? area;
  final bool complete;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final ground = MapGround.of(groundLook(context));
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: Corner.smallRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: MapGroundPainter(ground),
              foregroundPainter: _FramePainter(
                area,
                scheme.primary,
                solid: complete,
              ),
            ),
            if (area != null)
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(Space.xs),
                  child: complete
                      ? CircleAvatar(
                          radius: 10,
                          backgroundColor: scheme.primary,
                          child: Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: scheme.onPrimary,
                          ),
                        )
                      : SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                            color: warningColor(context),
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter(this.area, this.ink, {required this.solid});
  final Area? area;
  final Color ink;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    // Degrees of longitude shrink away from the equator.
    final a = area;
    var ratio = 1.4;
    if (a != null) {
      final squeeze = cos((a.south + a.north) / 2 * pi / 180);
      final tall = a.north - a.south;
      final wide = (a.east - a.west) * squeeze;
      if (tall > 0 && wide > 0) ratio = wide / tall;
    }
    final room = size.shortestSide * .62;
    final frame = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: ratio >= 1 ? room : room * ratio,
      height: ratio >= 1 ? room / ratio : room,
    );
    canvas.drawRect(
      frame,
      Paint()..color = ink.withValues(alpha: solid ? .18 : .06),
    );
    final edge = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (solid) {
      canvas.drawRect(frame, edge);
      return;
    }
    // Dashed while nothing, or not everything, is saved.
    final path = Path()..addRect(frame);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), edge);
      }
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.area != area || old.ink != ink || old.solid != solid;
}

/// Pan and zoom to the area to keep, then download it.
class _AreaPicker extends StatefulWidget {
  const _AreaPicker({required this.maps, required this.areaMapBuilder});

  final OfflineMaps maps;
  final AreaMapBuilder areaMapBuilder;

  @override
  State<_AreaPicker> createState() => _AreaPickerState();
}

class _AreaPickerState extends State<_AreaPicker> {
  final _name = TextEditingController();
  Area? _area;
  double? _progress;
  String? _error;
  StreamSubscription<double>? _download;

  @override
  void dispose() {
    _name.dispose();
    // A download keeps going without this screen; only stop listening.
    _download?.cancel();
    super.dispose();
  }

  void _start() {
    final area = _area;
    if (area == null) return;
    final name = _name.text.trim().isEmpty
        ? 'Area saved ${MaterialLocalizations.of(context).formatShortDate(DateTime.now())}'
        : _name.text.trim();
    setState(() {
      _progress = 0;
      _error = null;
    });
    _download = widget.maps
        .download(name, area)
        .listen(
          (progress) => setState(() => _progress = progress),
          onError: (Object error) => setState(() {
            _progress = null;
            _error = '$error';
          }),
          onDone: () {
            if (mounted && _error == null) Navigator.pop(context, true);
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final area = _area;
    final tiles = area == null ? null : tilesFor(area);
    final fits = area != null && fitsOneDownload(area);
    final text = Theme.of(context).textTheme;
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Download an area')),
      body: Column(
        children: [
          Expanded(
            child: widget.areaMapBuilder(
              (area) => setState(() => _area = area),
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'The map above is the area that will be kept.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(switch (tiles) {
                      null => 'Move the map to the area of your trip.',
                      _ when fits =>
                        'About $tiles map tiles · roughly '
                            '${megabytes(estimatedAreaBytes(area))} with '
                            'hill shading',
                      _ =>
                        'Too big for one download: about $tiles map tiles, roughly '
                            '${megabytes(estimatedBytes(tiles))} (the limit is '
                            '${OfflineLimits.tiles} tiles or 50 MB). Zoom in.',
                    }, style: text.bodyLarge),
                    if (_error case final error?)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error,
                          style: text.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (progress != null) ...[
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 8),
                      Text('Downloading… ${(progress * 100).round()} %'),
                    ] else ...[
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Name (optional)',
                          hintText: 'e.g. Spiti valley',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: fits ? _start : null,
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                      ),
                    ],
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
