import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../group/identity.dart';
import 'components.dart';
import 'identity_marker.dart';
import 'map_ground.dart';
import 'settings.dart';
import 'theme.dart';
import 'tokens.dart';

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
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.md,
            Space.gutter,
            Space.xl,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 408 - 2 * Space.gutter,
              ),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: Color(_colour.argb)),
                duration: Motion.of(context, Motion.standard),
                builder: (context, mine, _) => FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: mine,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    _saving
                        ? 'Saving…'
                        : widget.welcome
                        ? "Let's go"
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
                    padding: const EdgeInsets.all(Space.gutter),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MapSpecimen(
                          identity: _identity,
                          look: groundLook(context),
                          height: (MediaQuery.sizeOf(context).height * .34)
                              .clamp(200.0, 340.0),
                        ),
                        const SizedBox(height: Space.lg),
                        TextField(
                          controller: _name,
                          enabled: !_saving,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          maxLength: MapIdentity.nameLength,
                          decoration: const InputDecoration(
                            hintText: 'What do we call you?',
                            counterText: '',
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _saving ? null : _save(),
                        ),
                        const SizedBox(height: Space.xl),
                        LayoutBuilder(
                          builder: (context, box) => Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.sm,
                            children: [
                              for (final colour in IdentityColour.values)
                                _VisualChoice(
                                  label: colour.label,
                                  selected: _colour == colour,
                                  width: (box.maxWidth - 2 * Space.sm) / 3,
                                  height: Touch.primary,
                                  fill: Color(colour.argb),
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _colour = colour),
                                  child: _colour == colour
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 30,
                                          color: Colors.white,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        LayoutBuilder(
                          builder: (context, box) => Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (final shape in MarkerShape.values)
                                _VisualChoice(
                                  label: markerShapeLabel(shape),
                                  selected: _shape == shape,
                                  width: (box.maxWidth - 3 * Space.sm) / 4,
                                  height: Touch.primary,
                                  fill: _shape == shape
                                      ? Color(
                                          _colour.argb,
                                        ).withValues(alpha: .13)
                                      : raisedGround(context),
                                  outline: _shape == shape
                                      ? Color(_colour.argb)
                                      : scheme.outlineVariant,
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _shape = shape),
                                  child: IdentityMarker(
                                    identity: MapIdentity(
                                      name: _name.text,
                                      colour: _colour,
                                      shape: shape,
                                    ),
                                    size: 44,
                                    showInitials: false,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.lg),
                            child: Semantics(
                              liveRegion: true,
                              child: StatusNote(_error!, tone: NoteTone.error),
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
    required this.width,
    required this.height,
    required this.fill,
    this.outline,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final Widget child;
  final double width;
  final double height;
  final Color fill;
  final Color? outline;
  void _select() {
    HapticFeedback.selectionClick();
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
      child: AnimatedScale(
        scale: selected ? 1.05 : 1,
        duration: Motion.of(context, Motion.quick),
        curve: Curves.easeOutBack,
        child: SizedBox(
          width: width,
          height: height,
          child: Material(
            color: fill,
            shape: RoundedRectangleBorder(
              borderRadius: Corner.mediumRadius,
              side: BorderSide(color: outline ?? Colors.transparent, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed == null ? null : _select,
              excludeFromSemantics: true,
              splashFactory: NoSplash.splashFactory,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

/// You, as the map will draw you: your accuracy ring, your marker at a size
/// you can enjoy, and two neighbours at the size they really are.
class _MapSpecimen extends StatelessWidget {
  const _MapSpecimen({
    required this.identity,
    required this.look,
    required this.height,
  });
  final MapIdentity identity;
  final Look look;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ground = MapGround.of(look);
    final mine = Color(identity.colour.argb);
    final colours = [
      for (final c in IdentityColour.values)
        if (c != identity.colour) c,
    ];
    final shapes = [
      for (final s in MarkerShape.values)
        if (s != identity.shape) s,
    ];
    final ring = height * .82;
    Widget neighbour(String name, int i, Alignment at) => Align(
      alignment: at,
      child: ExcludeSemantics(
        child: IdentityMarker(
          identity: MapIdentity(
            name: name,
            colour: colours[i + 1],
            shape: shapes[i],
          ),
          size: 40,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: Corner.largeRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(painter: MapGroundPainter(ground)),
              ),
            ),
            ExcludeSemantics(
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.standard),
                width: ring,
                height: ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mine.withValues(alpha: .12),
                  border: Border.all(
                    color: mine.withValues(alpha: .5),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            neighbour('Asha', 0, const Alignment(-.72, -.5)),
            neighbour('Tom', 1, const Alignment(.74, .46)),
            Pop(
              trigger: (identity.colour, identity.shape),
              child: IdentityMarker(identity: identity, size: 96),
            ),
          ],
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
