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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.welcome ? null : AppBar(automaticallyImplyLeading: true),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving
                        ? 'Saving…'
                        : widget.welcome
                        ? 'Continue'
                        : 'Save',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 408),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 168,
                          width: double.infinity,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: ExcludeSemantics(
                                  child: CustomPaint(
                                    painter: _PreviewGround(scheme.onSurface),
                                  ),
                                ),
                              ),
                              IdentityMarker(identity: _identity, size: 88),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _name,
                          enabled: !_saving,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          maxLength: MapIdentity.nameLength,
                          decoration: InputDecoration(
                            hintText: 'Your name',
                            counterText: '',
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: scheme.outlineVariant,
                              ),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: scheme.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _saving ? null : _save(),
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final colour in IdentityColour.values)
                              _VisualChoice(
                                label: colour.label,
                                selected: _colour == colour,
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _colour = colour),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: _colour == colour
                                        ? Border.all(
                                            color: scheme.onSurface,
                                            width: 1.2,
                                          )
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Color(colour.argb),
                                      shape: BoxShape.circle,
                                    ),
                                    child: _colour == colour
                                        ? const Icon(
                                            Icons.check,
                                            size: 15,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final shape in MarkerShape.values)
                              _VisualChoice(
                                label: shape.label,
                                selected: _shape == shape,
                                width: 56,
                                height: 64,
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _shape = shape),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IdentityMarker(
                                      identity: MapIdentity(
                                        name: _name.text,
                                        colour: _colour,
                                        shape: shape,
                                      ),
                                      size: 36,
                                      showInitials: false,
                                    ),
                                    const SizedBox(height: 7),
                                    Container(
                                      width: 16,
                                      height: 2,
                                      color: _shape == shape
                                          ? scheme.onSurface
                                          : Colors.transparent,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
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
        ),
      ),
    );
  }
}

class _VisualChoice extends StatelessWidget {
  const _VisualChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.child,
    this.width = 48,
    this.height = 48,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final Widget child;
  final double width;
  final double height;
  void _select() {
    FocusManager.instance.primaryFocus?.unfocus();
    onPressed?.call();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    selected: selected,
    enabled: onPressed != null,
    onTap: onPressed == null ? null : _select,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      child: InkResponse(
        onTap: onPressed == null ? null : _select,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        excludeFromSemantics: true,
        radius: 28,
        child: SizedBox(
          width: width,
          height: height,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

/// Quiet contour lines place the actual marker in a map context, without copy.
class _PreviewGround extends CustomPainter {
  const _PreviewGround(this.ink);
  final Color ink;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink.withValues(alpha: .07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = 20.0 + i * 38;
      canvas.drawPath(
        Path()
          ..moveTo(0, y + 30)
          ..cubicTo(
            size.width * .3,
            y - 50,
            size.width * .65,
            y + 70,
            size.width,
            y - 5,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewGround old) => old.ink != ink;
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
