import 'package:flutter/material.dart';

import '../group/identity.dart';
import 'identity_marker.dart';
import 'settings.dart';

/// One screen, before GPS/recording, also reused for editing at any time.
class IdentityScreen extends StatefulWidget {
  const IdentityScreen({
    super.key,
    required this.settings,
    this.welcome = false,
    this.onSaved,
  });
  final Settings settings;
  final bool welcome;
  final VoidCallback? onSaved;
  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  late final _name = TextEditingController(
    text: widget.settings.name.value ?? '',
  );
  late var _colour = widget.settings.identity.value.colour;
  late var _shape = widget.settings.identity.value.shape;
  bool _saving = false;
  String? _error;
  MapIdentity get _identity =>
      MapIdentity(name: _name.text, colour: _colour, shape: _shape);
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.settings.setIdentity(_identity);
      if (!mounted) return;
      if (widget.onSaved case final saved?) {
        saved();
      } else {
        Navigator.pop(context, true);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your marker. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.welcome,
        title: Text(
          widget.welcome ? 'Welcome to Tripping' : 'Your map identity',
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : widget.welcome
                    ? 'Let’s go'
                    : 'Save identity',
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Find yourself on the map', style: text.headlineSmall),
                    const SizedBox(height: 6),
                    const Text(
                      'A name and a mark your companions can recognise.',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          IdentityMarker(identity: _identity, size: 72),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _identity.displayName,
                                  style: text.titleMedium,
                                ),
                                Text('${_colour.label} · ${_shape.label}'),
                                const Text('Your map marker'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      maxLength: MapIdentity.nameLength,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        hintText: 'Traveller',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _saving ? null : _save(),
                    ),
                    const SizedBox(height: 14),
                    Text('Colour', style: text.titleSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final colour in IdentityColour.values)
                          Semantics(
                            selected: _colour == colour,
                            child: ChoiceChip(
                              avatar: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Color(colour.argb),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              label: Text(colour.label),
                              selected: _colour == colour,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              onSelected: _saving
                                  ? null
                                  : (_) => setState(() => _colour = colour),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Shape', style: text.titleSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final shape in MarkerShape.values)
                          Semantics(
                            selected: _shape == shape,
                            child: ChoiceChip(
                              avatar: ExcludeSemantics(
                                child: IdentityMarker(
                                  identity: MapIdentity(
                                    name: _name.text,
                                    colour: _colour,
                                    shape: shape,
                                  ),
                                  size: 28,
                                ),
                              ),
                              label: Text(shape.label),
                              selected: _shape == shape,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              onSelected: _saving
                                  ? null
                                  : (_) => setState(() => _shape = shape),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Change your mark any time from “Your map identity”.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_error!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class IdentityGate extends StatelessWidget {
  const IdentityGate({super.key, required this.settings, required this.child});
  final Settings settings;
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: settings.identity,
    builder: (context, _, _) => settings.identityReady
        ? child
        : IdentityScreen(settings: settings, welcome: true, onSaved: () {}),
  );
}
