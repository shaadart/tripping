import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../group/invite.dart';
import '../journey/journey.dart';
import 'settings.dart';
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
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              IdentityMarker(identity: invite.identity),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${invite.hostName} · ${invite.colour.label} · ${invite.shape.label}',
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            // Dark on white whatever the look: scanners need the contrast.
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: invite.link,
                size: 240,
                backgroundColor: Colors.white,
                semanticsLabel: 'Invite code',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Companions open Tripping, choose "Join a group" and scan this, '
            'or open the link you send them.',
            style: text.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => (share ?? _shareText)(
              'Join my group on Tripping:\n${invite.link}',
            ),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share invite link'),
          ),
          const SizedBox(height: 24),
          Text(
            'Anyone with this code or link can join. Share it only with '
            'your companions.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            groupNote,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    final invite = _invite;
    return Scaffold(
      appBar: AppBar(title: const Text('Join a group')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (invite != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: IdentityMarker(identity: invite.identity, size: 64),
            ),
            const SizedBox(height: 12),
          ],
          if (invite == null) ...[
            Text(
              'Scan the invite code on a companion\'s phone, or paste the '
              'invite link they sent you.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan invite code'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste invite link'),
            ),
            if (_problem case final problem?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  problem,
                  style: text.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
          ] else ...[
            Text('Join ${invite.hostName}\'s group?', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Joining is saved on this phone, with your journey.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              groupNote,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
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
                const SizedBox(height: 8),
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
                Text(
                  'This journey is already in a group. End it to join '
                  'another.',
                  style: text.bodyLarge,
                ),
              ],
            },
          ],
        ],
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
    body: MobileScanner(
      controller: _camera,
      onDetect: _detected,
      errorBuilder: (context, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
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
  );
}
