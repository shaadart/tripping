import 'dart:async';

import 'package:flutter/material.dart';

import '../map/offline_area.dart';
import '../map/offline_maps.dart';

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.download_for_offline_outlined),
        label: const Text('Download an area'),
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
            return const _Message(
              'No offline maps yet.\n\nDownload the areas of a trip while you '
              'have internet. They work without a connection, under your '
              'track, waypoints and position.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              FutureBuilder(
                future: _newest,
                builder: (context, snapshot) {
                  final newest = snapshot.data;
                  final stale = newest == null
                      ? 0
                      : areas
                            .where((a) => a.release != newest || !a.complete)
                            .length;
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
                ListTile(
                  leading: Icon(
                    area.complete
                        ? Icons.offline_pin_outlined
                        : Icons.downloading_outlined,
                  ),
                  title: Text(area.name),
                  subtitle: Text(
                    area.complete
                        ? '${megabytes(area.bytes)} · saved '
                              '${_day(context, area.savedAt)}'
                        : 'Incomplete (${(area.progress * 100).round()} %): '
                              'delete it and download again',
                    style: text.bodyMedium,
                  ),
                  trailing: IconButton(
                    onPressed: () => _delete(area),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete ${area.name}',
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Newer map data is available', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${stale == 1 ? 'One saved area uses' : '$stale saved areas use'} '
              'older map data. They still work offline; update them to add '
              'new areas. The old copies stay until the update has finished.',
              style: text.bodyMedium,
            ),
            if (error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$error Nothing was changed.',
                  style: text.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
            const SizedBox(height: 12),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
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
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
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
                            '${megabytes(estimatedBytes(tiles))}',
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
