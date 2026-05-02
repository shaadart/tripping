import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../group/identity.dart';
import 'components.dart';
import 'identity_marker.dart';
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
                          look: _look(context),
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

/// The map's own ground colours, so the preview shows the marker where it
/// will live. Values follow tool/map_styles.dart.
class _MapGround {
  const _MapGround({
    required this.land,
    required this.park,
    required this.water,
    required this.road,
    required this.casing,
    required this.minor,
  });
  final Color land, park, water, road, casing, minor;

  static const light = _MapGround(
    land: Color(0xFFF8F8F3),
    park: Color(0xFFE8EFDE),
    water: Color(0xFFD1E6EC),
    road: Color(0xFFFFFFFF),
    casing: Color(0xFFE2DFD3),
    minor: Color(0xFFECEAE0),
  );
  static const dark = _MapGround(
    land: Color(0xFF141E20),
    park: Color(0xFF1D3026),
    water: Color(0xFF183743),
    road: Color(0xFF2C3C3F),
    casing: Color(0xFF0E1618),
    minor: Color(0xFF1F2C2F),
  );
}

Look _look(BuildContext context) {
  final theme = Theme.of(context);
  return theme.extension<TrippingLook>()?.look ??
      (theme.brightness == Brightness.dark ? Look.dark : Look.light);
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
    final ground = look == Look.dark ? _MapGround.dark : _MapGround.light;
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
                child: CustomPaint(painter: _MapPainter(ground)),
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
            _Pop(
              trigger: (identity.colour, identity.shape),
              child: IdentityMarker(identity: identity, size: 96),
            ),
          ],
        ),
      ),
    );
  }
}

/// Springs its child whenever [trigger] changes: a reply to a choice, never
/// ambient. No motion at all when the system asks for none.
class _Pop extends StatefulWidget {
  const _Pop({required this.trigger, required this.child});
  final Object trigger;
  final Widget child;
  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  late final _scale = Tween(
    begin: .8,
    end: 1.0,
  ).chain(CurveTween(curve: Curves.elasticOut)).animate(_controller);

  @override
  void didUpdateWidget(_Pop old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _controller.duration = Motion.of(
        context,
        const Duration(milliseconds: 420),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

/// A few blocks of park, a river and crossing streets, drawn to the card.
class _MapPainter extends CustomPainter {
  const _MapPainter(this.ground);
  final _MapGround ground;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint fill(Color c) => Paint()..color = c;
    Paint line(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawRect(Offset.zero & size, fill(ground.land));
    for (final r in [
      Rect.fromLTRB(w * .04, h * .08, w * .36, h * .44),
      Rect.fromLTRB(w * .66, h * .6, w * 1.04, h * 1.06),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(28)),
        fill(ground.park),
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(-w * .05, h * .8)
        ..cubicTo(w * .3, h * 1.0, w * .5, h * .58, w * 1.05, h * .74),
      line(ground.water, 26),
    );
    for (final y in [.2, .62]) {
      canvas.drawLine(
        Offset(0, h * y),
        Offset(w, h * (y + .06)),
        line(ground.minor, 4),
      );
    }
    final main = Path()
      ..moveTo(-w * .05, h * .34)
      ..cubicTo(w * .35, h * .2, w * .6, h * .5, w * 1.05, h * .34);
    final cross = Path()
      ..moveTo(w * .54, -h * .05)
      ..quadraticBezierTo(w * .44, h * .5, w * .6, h * 1.05);
    for (final path in [main, cross]) {
      canvas.drawPath(path, line(ground.casing, 15));
    }
    for (final path in [main, cross]) {
      canvas.drawPath(path, line(ground.road, 11));
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.ground != ground;
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
