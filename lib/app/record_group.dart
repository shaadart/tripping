import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../group/convoy.dart';
import '../group/group_sync.dart';
import '../group/sharing.dart';
import 'format.dart';
import 'identity_marker.dart';

/// The journey's group, in plain words: reachable or not, and each
/// companion's position with its age, from their newest saved fix. An old
/// position is said to be old, never shown as current.
class GroupLine extends StatelessWidget {
  const GroupLine({
    super.key,
    required this.membership,
    required this.paused,
    required this.sharingPaused,
    required this.onToggleSharing,
    required this.status,
    required this.now,
    required this.here,
    required this.onInvite,
    required this.onJoin,
    required this.onLeave,
    required this.convoy,
  });

  final MembershipRow? membership;
  final bool paused;
  final bool sharingPaused;
  final VoidCallback? onToggleSharing;

  /// Measures companions along this phone's road route, if any.
  final Convoy? convoy;
  final ValueListenable<GroupStatus?>? status;
  final DateTime now;

  /// This phone's newest fix, to say how far companions are.
  final Fix? here;
  final VoidCallback onInvite;
  final VoidCallback onJoin;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final membership = this.membership;
    if (membership == null) {
      return Wrap(
        children: [
          TextButton.icon(
            onPressed: onInvite,
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Invite companions'),
          ),
          TextButton(onPressed: onJoin, child: const Text('Join a group')),
        ],
      );
    }
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final host = membership.hostName;
    final inviter = membership.role == GroupRole.creator;
    final title = inviter ? 'Your group' : "In ${host ?? 'a'}'s group";
    Widget body(GroupStatus? status) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.titleMedium),
        Text(
          paused
              ? 'Journey paused · group updates stopped until you resume'
              : sharingPaused
              ? 'Sharing paused · recording stays on this phone'
              : switch (status) {
                  null => 'Not connected: positions are not shared',
                  GroupStatus(:final problem?) => problem,
                  GroupStatus(suspended: true) => 'Group updates paused',
                  GroupStatus(ended: true) =>
                    'This group was closed: nothing is shared now',
                  GroupStatus(refused: true) =>
                    "The group isn't accepting this phone's updates: leave and "
                        'join again',
                  GroupStatus(connected: false, :final offlineSince?) =>
                    'Offline since ${timeOfDay(context, offlineSince)} · sharing '
                        'resumes when the connection returns',
                  GroupStatus(connected: false) =>
                    "Not connected: the group can't see this phone now",
                  GroupStatus(connected: true, :final sentAt?) =>
                    'Connected · the group received your position '
                        '${age(_atLeastZero(now.difference(sentAt)))} ago',
                  GroupStatus(connected: true) =>
                    'Connected · sharing your position with the group',
                },
          style: muted,
        ),
        if (status != null && !status.ended) ...[
          for (final companion in _inConvoyOrder(status.companions))
            _companion(companion, text, muted),
          if (status.connected && status.heard && status.companions.isEmpty)
            Text('No one else has joined yet', style: muted),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.group_outlined, color: scheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: switch (status) {
              final status? => ValueListenableBuilder(
                valueListenable: status,
                builder: (context, value, _) => body(value),
              ),
              null => body(null),
            },
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton(onPressed: onInvite, child: const Text('Invite')),
              if (onToggleSharing != null)
                TextButton(
                  onPressed: onToggleSharing,
                  child: Text(
                    sharingPaused ? 'Resume sharing' : 'Pause sharing',
                  ),
                ),
              TextButton(onPressed: onLeave, child: const Text('Leave group')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _companion(Companion companion, TextTheme text, TextStyle? muted) =>
      MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IdentityMarker(
              identity: companion.shared.identity,
              hollow:
                  companion.shared.phase != JourneyPhase.recording ||
                  companion.positionAt == null ||
                  freshnessOf(
                        _atLeastZero(now.difference(companion.positionAt!)),
                        companion.shared.mode,
                      ) ==
                      Freshness.stale,
            ),
            const SizedBox(width: 8),
            Expanded(child: _companionText(companion, text, muted)),
          ],
        ),
      );

  Widget _companionText(Companion companion, TextTheme text, TextStyle? muted) {
    final shared = companion.shared;
    final fix = shared.fix;
    final here = this.here;
    if (shared.phase == JourneyPhase.ended) {
      return Text(
        '${shared.name} · ended their journey · '
        '${age(_atLeastZero(now.difference(companion.heardAt)))} ago',
        style: muted,
      );
    }
    if (fix == null) {
      return Text(
        '${shared.name} · no position yet · heard '
        '${age(_atLeastZero(now.difference(companion.heardAt)))} ago',
        style: muted,
      );
    }
    final old = _atLeastZero(now.difference(companion.positionAt ?? fix.time));
    final still = companion.stillSince;
    final freshness = freshnessOf(old, shared.mode);
    return Text(
      [
        shared.name,
        if (here != null)
          convoy?.gapText(here, fix) ?? distanceAndDirection(here, fix),
        if (shared.phase == JourneyPhase.paused) 'paused',
        if (still != null)
          'stopped ${age(_atLeastZero(now.difference(still)))}',
        switch (freshness) {
          Freshness.stale => 'last seen ${age(old)} ago',
          _ => '${age(old)} ago',
        },
        // Their own word that they have this phone's position, and which.
        if (companion.hasMineFrom case final mine?)
          'has yours from ${age(_atLeastZero(now.difference(mine)))} ago',
      ].join(' · '),
      style: freshness == Freshness.live ? text.bodyMedium : muted,
    );
  }

  /// Along a road route, the leader first; otherwise newest heard first.
  List<Companion> _inConvoyOrder(List<Companion> companions) {
    final convoy = this.convoy;
    if (convoy == null) return companions;
    double rank(Companion c) {
      final fix = c.shared.fix;
      return (fix == null ? null : convoy.alongOf(fix)) ??
          double.negativeInfinity;
    }

    return [...companions]..sort((a, b) => rank(b).compareTo(rank(a)));
  }

  /// Clocks disagree by a little; an age is never negative.
  static Duration _atLeastZero(Duration age) =>
      age.isNegative ? Duration.zero : age;
}
