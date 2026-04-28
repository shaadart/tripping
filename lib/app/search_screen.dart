import 'dart:async';

import 'package:flutter/material.dart';

import '../journey/geo.dart';
import '../places/place.dart';
import '../places/place_search.dart';
import 'format.dart';

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

  String? _away(Place place) {
    final near = widget.near;
    if (near == null || !widget.distances) return null;
    final meters = metersBetween(
      near.$1,
      near.$2,
      place.latitude,
      place.longitude,
    );
    return '${kilometres(meters)} away';
  }

  Widget _list(List<Place> places) => ListView(
    children: [
      for (final place in places)
        ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(place.name),
          subtitle: Text(
            [place.detail, _away(place)].whereType<String>().join(' · '),
          ),
          onTap: () => Navigator.pop(context, place),
        ),
    ],
  );

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
            border: InputBorder.none,
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
                error.offline
                    ? 'Search needs a connection.\n\nYou can still pick a '
                          'destination on the map: long-press the place and '
                          'choose "Go here".'
                    : error.message,
              ),
              (null, final results?) when results.isEmpty => const _Note(
                'Nothing found. Try another spelling, or a nearby town.',
              ),
              (null, final results?) => _list(results),
              _ => FutureBuilder(
                future: _recent,
                builder: (context, snapshot) {
                  final recent = snapshot.data ?? const [];
                  if (recent.isEmpty) {
                    return _Note(
                      _query.isEmpty
                          ? 'Type a town, a place or an address.'
                          : 'Keep typing…',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text('Recent', style: text.titleSmall),
                      ),
                      Expanded(child: _list(recent)),
                    ],
                  );
                },
              ),
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
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

class _Note extends StatelessWidget {
  const _Note(this.text);

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
