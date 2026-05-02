import 'package:flutter/material.dart';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../map/map_symbols.dart';
import 'components.dart';
import 'format.dart';
import 'tokens.dart';

/// Names, notes or deletes a waypoint that has just been saved. The place
/// itself is already on disk when this opens, so closing it loses nothing.
Future<void> showWaypointSheet(
  BuildContext context, {
  required JourneyStore store,
  required WaypointRow waypoint,
  String? warning,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) =>
      _WaypointSheet(store: store, waypoint: waypoint, warning: warning),
);

class _WaypointSheet extends StatefulWidget {
  const _WaypointSheet({
    required this.store,
    required this.waypoint,
    this.warning,
  });

  final JourneyStore store;
  final WaypointRow waypoint;

  /// Something the user should know about where this was marked.
  final String? warning;

  @override
  State<_WaypointSheet> createState() => _WaypointSheetState();
}

class _WaypointSheetState extends State<_WaypointSheet> {
  late final _name = TextEditingController(text: widget.waypoint.name);
  late final _note = TextEditingController(text: widget.waypoint.note);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.store.describeWaypoint(
      widget.waypoint.id,
      name: _name.text,
      note: _note.text,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await widget.store.deleteWaypoint(widget.waypoint.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final waypoint = widget.waypoint;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final marked = waypoint.kind == WaypointKind.marked;
    final accuracy = waypoint.accuracy;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                child: MapSymbolGlyph(
                  marked ? MapSymbol.marked : MapSymbol.planned,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      marked ? 'Marked here' : 'Planned point',
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        coordinatesText(waypoint.latitude, waypoint.longitude),
                        if (accuracy != null) '±${accuracy.round()} m',
                      ].join(' '),
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.warning case final warning?)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: StatusNote(warning),
            ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(Touch.secondary),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
