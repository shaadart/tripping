import 'package:flutter/material.dart';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import 'format.dart';
import 'theme.dart';

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
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            marked ? 'Marked here' : 'Planned point',
            style: text.titleLarge,
          ),
          const SizedBox(height: 4),
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
          if (widget.warning case final warning?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                warning,
                style: text.bodyMedium?.copyWith(color: warningColor(context)),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(onPressed: _delete, child: const Text('Delete')),
              const Spacer(),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(minimumSize: const Size(120, 56)),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
