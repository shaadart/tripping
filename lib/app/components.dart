import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';

/// Ground for anything that sits above the map or the canvas: fields, cards,
/// sheets and floating controls share it.
Color raisedGround(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHighest;

BorderSide _hairline(BuildContext context) =>
    BorderSide(color: Theme.of(context).colorScheme.outlineVariant);

/// A control or label floating on the map: raised ground, hairline edge, one
/// corner radius. Buttons inside it keep their own 48 dp targets.
class MapChrome extends StatelessWidget {
  const MapChrome({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Material(
    color: raisedGround(context),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: Corner.mediumRadius,
      side: _hairline(context),
    ),
    child: padding == null ? child : Padding(padding: padding!, child: child),
  );
}

/// The panel at the foot of the map: raised ground, rounded top, hairline.
class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: raisedGround(context),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: Corner.sheetRadius,
      side: _hairline(context),
    ),
    child: child,
  );
}

/// How serious a [StatusNote] is.
enum NoteTone { warning, error }

/// Something is wrong or at risk, in plain words, with at most one way to put
/// it right. Healthy states are not notes: they stay quiet.
class StatusNote extends StatelessWidget {
  const StatusNote(
    this.message, {
    super.key,
    this.tone = NoteTone.warning,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final NoteTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = tone == NoteTone.error
        ? theme.colorScheme.error
        : warningColor(context);
    final label = actionLabel;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colour.withValues(alpha: .1),
          raisedGround(context),
        ),
        borderRadius: Corner.smallRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                tone == NoteTone.error
                    ? Icons.error_outline_rounded
                    : Icons.warning_amber_rounded,
                color: colour,
                size: 22,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: theme.textTheme.bodyLarge),
                  if (label != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: OutlinedButton(
                        onPressed: onAction,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, Touch.min),
                        ),
                        child: Text(label),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Springs its child whenever [trigger] changes: a reply to a choice, never
/// ambient. No motion at all when the system asks for none.
class Pop extends StatefulWidget {
  const Pop({super.key, required this.trigger, required this.child});
  final Object trigger;
  final Widget child;
  @override
  State<Pop> createState() => _PopState();
}

class _PopState extends State<Pop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  late final _scale = Tween(
    begin: .8,
    end: 1.0,
  ).chain(CurveTween(curve: Curves.elasticOut)).animate(_controller);

  @override
  void didUpdateWidget(Pop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
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
