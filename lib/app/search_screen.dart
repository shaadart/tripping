import 'dart:async';

import 'package:flutter/material.dart';

import '../journey/geo.dart';
import '../places/place.dart';
import '../places/place_search.dart';
import 'components.dart';
import 'format.dart';
import 'tokens.dart';
import '../map/map_symbols.dart';

/// Finds a place to go. Pops the chosen [Place], or nothing.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.search,
    required this.recent,
    this.near,
    this.distances = true,
  });

  final PlaceSearch search;

  /// Places chosen before, shown while nothing is typed.
  final Future<List<Place>> Function() recent;

  /// Where the phone is or was last known to be, to favour results near it.
  final (double, double)? near;

  /// Whether to say how far each result is from [near]: only when [near] is
  /// recent, or the distances would mislead.
  final bool distances;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  /// Quiet typing time before asking: one request per pause, not per key.
  static const _settle = Duration(milliseconds: 400);

  late final Future<List<Place>> _recent = widget.recent();
  final _field = TextEditingController();
  Timer? _debounce;
  int _asked = 0;
  String _query = '';
  List<Place>? _results;
  SearchError? _error;
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _debounce?.cancel();
    setState(() {
      _query = text.trim();
      _error = null;
      if (_query.length < PhotonSearch.minLength) _results = null;
    });
    if (_query.length < PhotonSearch.minLength) return;
    _debounce = Timer(_settle, () => _ask(_query));
  }

  Future<void> _ask(String query) async {
    final asked = ++_asked;
    setState(() => _busy = true);
    try {
      final near = widget.near;
      final places = await widget.search.search(
        query,
        nearLatitude: near?.$1,
        nearLongitude: near?.$2,
      );
      // Typing went on meanwhile: an older answer must not replace a newer.
      if (!mounted || asked != _asked) return;
      setState(() {
        _results = places;
        _error = null;
      });
    } on SearchError catch (error) {
      if (!mounted || asked != _asked) return;
      setState(() => _error = error);
    } finally {
      if (mounted && asked == _asked) setState(() => _busy = false);
    }
  }

  /// How far a place is, while the last position still says where we are.
  String? _away(Place place) {
    final near = widget.near;
    if (near == null || !widget.distances) return null;
    return kilometres(
      metersBetween(near.$1, near.$2, place.latitude, place.longitude),
    );
  }

  Widget _list(List<Place> places, {bool recent = false}) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xs,
        Space.gutter,
        Space.lg,
      ),
      itemCount: places.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) {
        final place = places[i];
        final away = _away(place);
        return MapChrome(
          child: InkWell(
            onTap: () => Navigator.pop(context, place),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Touch.secondary),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: recent
                          ? Icon(Icons.history_rounded, color: muted)
                          : const FittedBox(
                              child: MapSymbolGlyph(MapSymbol.destination),
                            ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (place.detail case final detail?)
                            Text(
                              detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(color: muted),
                            ),
                        ],
                      ),
                    ),
                    if (away != null) ...[
                      const SizedBox(width: Space.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            away,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            'away',
                            style: text.bodySmall?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final error = _error;
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _field,
          autofocus: true,
          onChanged: _typed,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            _debounce?.cancel();
            if (value.trim().length >= PhotonSearch.minLength) {
              unawaited(_ask(value.trim()));
            }
          },
          decoration: const InputDecoration(
            hintText: 'Search a place',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
        ),
        // Always there, so the field is never rebuilt (and emptied) when
        // the bar comes and goes.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _busy
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: switch ((error, results)) {
              (final error?, _) => _Note(
                icon: error.offline
                    ? Icons.cloud_off_rounded
                    : Icons.error_outline_rounded,
                error.offline
                    ? 'Search needs a connection.\n\nYou can still pick a '
                          'destination on the map: long-press the place and '
                          'choose "Go here".'
                    : error.message,
              ),
              (null, final results?) when results.isEmpty => const _Note(
                icon: Icons.travel_explore_rounded,
                'Nothing found. Try another spelling, or a nearby town.',
              ),
              (null, final results?) => _list(results),
              _ => FutureBuilder(
                future: _recent,
                builder: (context, snapshot) {
                  final recent = snapshot.data ?? const [];
                  if (recent.isEmpty) {
                    return _Note(
                      icon: Icons.place_outlined,
                      _query.isEmpty
                          ? 'Type a town, a place or an address.'
                          : 'Keep typing…',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.gutter,
                          Space.lg,
                          Space.gutter,
                          Space.sm,
                        ),
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Recent',
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: muted,
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: _list(recent, recent: true)),
                    ],
                  );
                },
              ),
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Text(
                'Search by Photon · Data © OpenStreetMap contributors',
                style: text.bodySmall?.copyWith(color: muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet moment in the search: a large icon that says what kind, and the
/// words beneath.
class _Note extends StatelessWidget {
  const _Note(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: scheme.primary),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
