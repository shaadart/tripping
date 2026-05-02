import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../group/invite.dart';
import '../journey/journey.dart';
import 'components.dart';
import 'settings.dart';
import 'tokens.dart';
import 'identity_screen.dart';
import 'identity_marker.dart';

/// Says, in one place, what joining a group means (D-037): joining is the
/// choice to share; pausing leaves the last point; ending the journey or
/// leaving stops sharing. A scan or a join is never connectivity.
const groupNote =
    'Everyone in the group sees your position while your journey records. '
    'Pausing shows them where you paused; ending your journey or leaving '
    'the group stops sharing. Positions are sealed: the relay cannot read '
    'them. Joining is saved on this phone, even without a connection.';

/// [groupNote], one fact at a time, each with the sign that shows it.
const groupFacts = <(IconData, String)>[
  (
    Icons.my_location_rounded,
    'Everyone in the group sees your position while your journey records.',
  ),
  (
    Icons.pause_circle_outline_rounded,
    'Pausing shows them where you paused; ending your journey or leaving '
        'the group stops sharing.',
  ),
  (
    Icons.lock_outline_rounded,
    'Positions are sealed: the relay cannot read them.',
  ),
  (
    Icons.save_outlined,
    'Joining is saved on this phone, even without a connection.',
  ),
];

/// [groupFacts] as quiet rows.
class GroupFacts extends StatelessWidget {
  const GroupFacts({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (icon, fact) in groupFacts)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: 22, color: scheme.primary),
                ),
                const SizedBox(width: Space.md),
                Expanded(child: Text(fact, style: text.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The user's name for groups: the one saved, or asked for once. Null if
/// they back out.
Future<String?> nameForGroups(BuildContext context, Settings settings) async {
  final saved = settings.name.value;
  if (saved != null && saved.isNotEmpty) return saved;
  final savedIdentity = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => IdentityScreen(settings: settings)),
  );
  return savedIdentity == true ? settings.name.value : null;
}

/// Shows the invitation to the group as a QR code and a shareable link.
class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key, required this.invite, this.share});

  final Invite invite;

  /// Hands the text to other apps; injected so tests need no platform.
  final Future<void> Function(String text)? share;

  static Future<void> _shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Invite companions')),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          MapChrome(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    IdentityMarker(identity: invite.identity, size: 48),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        invite.hostName,
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                // Dark on white whatever the look: scanners need the
                // contrast.
                ClipRRect(
                  borderRadius: Corner.mediumRadius,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: QrImageView(
                        data: invite.link,
                        size: 232,
                        backgroundColor: Colors.white,
                        semanticsLabel: 'Invite code',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.md),
                Text(
                  'Companions choose "Join a group" and scan this, or open '
                  'the link you send them.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: () => (share ?? _shareText)(
              'Join my group on Tripping:\n${invite.link}',
            ),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share invite link'),
          ),
          const SizedBox(height: Space.lg),
          const StatusNote(
            'Anyone with this code or link can join. Share it only with your '
            'companions.',
          ),
          const GroupFacts(),
        ],
      ),
    );
  }
}

/// Where a join will go: the journey being recorded, or a new one.
enum JoinPlace {
  /// No journey yet: joining starts one.
  startJourney,

  /// A journey is under way and in no group.
  thisJourney,

  /// A journey is under way and already in a group.
  alreadyInGroup,
}

/// What the user chose on the join screen.
typedef JoinChoice = ({Invite invite, JourneyMode? start});

/// Finds an invitation (scanned, pasted, or from a link) and confirms
/// joining. Pops a [JoinChoice], or nothing.
class JoinScreen extends StatefulWidget {
  const JoinScreen({
    super.key,
    required this.place,
    this.invite,
    this.scannerBuilder,
  });

  final JoinPlace place;

  /// From a link that opened the app.
  final Invite? invite;

  /// Builds the camera scanner; injected so tests need no camera.
  final WidgetBuilder? scannerBuilder;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late Invite? _invite = widget.invite;
  String? _problem;

  Future<void> _scan() async {
    final found = await Navigator.of(context).push<Invite>(
      MaterialPageRoute(
        builder: widget.scannerBuilder ?? (_) => const ScanScreen(),
      ),
    );
    if (found != null && mounted) {
      setState(() {
        _invite = found;
        _problem = null;
      });
    }
  }

  Future<void> _paste() async {
    final copied = await Clipboard.getData(Clipboard.kTextPlain);
    final found = Invite.find(copied?.text ?? '');
    if (!mounted) return;
    setState(() {
      _invite = found ?? _invite;
      _problem = found == null
          ? 'What was copied holds no Tripping invite. Copy the whole '
                'message or link, then try again.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final invite = _invite;
    return Scaffold(
      appBar: AppBar(title: const Text('Join a group')),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          if (invite == null) ...[
            Row(
              children: [
                Expanded(
                  child: _JoinTile(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Scan invite code',
                    onPressed: _scan,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _JoinTile(
                    icon: Icons.content_paste_rounded,
                    label: 'Paste invite link',
                    onPressed: _paste,
                  ),
                ),
              ],
            ),
            if (_problem case final problem?)
              Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: StatusNote(problem, tone: NoteTone.error),
              ),
          ] else ...[
            Center(child: IdentityMarker(identity: invite.identity, size: 96)),
            const SizedBox(height: Space.md),
            Text(
              'Join ${invite.hostName}\'s group?',
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const GroupFacts(),
            const SizedBox(height: Space.xl),
            ...switch (widget.place) {
              JoinPlace.startJourney => [
                FilledButton.icon(
                  onPressed: () => Navigator.pop<JoinChoice>(context, (
                    invite: invite,
                    start: JourneyMode.road,
                  )),
                  icon: const Icon(Icons.directions_car_outlined),
                  label: const Text('Join and start a road journey'),
                ),
                const SizedBox(height: Space.sm),
                FilledButton.icon(
                  onPressed: () => Navigator.pop<JoinChoice>(context, (
                    invite: invite,
                    start: JourneyMode.expedition,
                  )),
                  icon: const Icon(Icons.hiking),
                  label: const Text('Join and start an expedition'),
                ),
              ],
              JoinPlace.thisJourney => [
                FilledButton(
                  onPressed: () => Navigator.pop<JoinChoice>(context, (
                    invite: invite,
                    start: null,
                  )),
                  child: const Text('Join with this journey'),
                ),
              ],
              JoinPlace.alreadyInGroup => [
                const StatusNote(
                  'This journey is already in a group. End it to join '
                  'another.',
                ),
              ],
            },
          ],
        ],
      ),
    );
  }
}

/// One way in: a big icon and its name on raised ground.
class _JoinTile extends StatelessWidget {
  const _JoinTile({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MapChrome(
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 40, color: scheme.primary),
                const SizedBox(height: Space.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The camera, looking for an invite code. Pops the [Invite] found.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _camera = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _done = false;
  DateTime? _toldAt;

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final invite = Invite.find(code.rawValue ?? '');
      if (invite != null) {
        _done = true;
        Navigator.pop(context, invite);
        return;
      }
    }
    // Not ours: say so, but not on every frame.
    final now = DateTime.now();
    if (_toldAt == null || now.difference(_toldAt!).inSeconds >= 3) {
      _toldAt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That code is not a Tripping invite.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan invite code')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _camera,
          onDetect: _detected,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.xxl),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Tripping needs the camera to scan the code. Allow it in '
                          'the system settings, or paste the invite link instead.'
                    : 'The camera could not start. Paste the invite link '
                          'instead.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        // Where to hold the code: four corners, nothing more.
        IgnorePointer(
          child: Center(
            child: SizedBox.square(
              dimension: 240,
              child: CustomPaint(
                painter: _Viewfinder(Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Viewfinder extends CustomPainter {
  const _Viewfinder(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const arm = 36.0, r = 18.0;
    final w = size.width, h = size.height;
    for (final (x, y, dx, dy) in [
      (0.0, 0.0, 1.0, 1.0),
      (w, 0.0, -1.0, 1.0),
      (0.0, h, 1.0, -1.0),
      (w, h, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * arm)
          ..lineTo(x, y + dy * r)
          ..quadraticBezierTo(x, y, x + dx * r, y)
          ..lineTo(x + dx * arm, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Viewfinder old) => old.ink != ink;
}
