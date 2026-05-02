import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../map/offline_maps.dart';
import '../map/map_key.dart';
import '../places/place.dart';
import '../places/place_search.dart';
import '../places/polyline.dart';
import '../routing/route_planner.dart';
import '../routing/route_progress.dart';
import '../routing/router.dart';
import '../recording/course.dart';
import '../recording/location_source.dart';
import '../recording/recorder.dart';
import '../group/convoy.dart';
import '../group/group_sync.dart';
import '../group/invite.dart';
import '../group/identity.dart';
import '../group/sharing.dart';
import 'components.dart';
import 'format.dart';
import 'group_screens.dart';
import 'record_chrome.dart';
import 'record_destination.dart';
import 'record_group.dart';
import 'record_readout.dart';
import 'record_status.dart';
import 'settings.dart';
import 'identity_screen.dart';
import 'identity_marker.dart';
import 'system_access.dart';
import 'search_screen.dart';
import 'theme.dart';
import 'tokens.dart';
import 'waypoint_sheet.dart';

/// How long a position still counts as where the phone is, for saying how
/// far search results are.
const _nearFreshFor = Duration(minutes: 10);

/// At most one new way a minute, after leaving the road or while a
/// connection is missing: the routing service is shared and fair-use.
const _replanEvery = Duration(minutes: 1);

/// One journey at a time: its numbers, one main action, and plain words
/// about anything that is wrong. The map takes the centre in M1.
class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.recorder,
    required this.location,
    required this.system,
    required this.mapBuilder,
    this.waypoints,
    this.historyBuilder,
    this.offlineMapsBuilder,
    this.savedOffline,
    this.places,
    this.planner,
    this.settings,
    this.group,
    this.scannerBuilder,
    this.shareText,
    this.onToggleHighSun,
    this.onMapNetworkChanged,
    this.clock = _utcNow,
  });

  final Recorder recorder;
  final LocationSource location;
  final SystemAccess system;

  /// Builds the map behind the panel; injected so tests need no platform map.
  final Widget Function(RecorderState state, DateTime now) mapBuilder;

  /// Where marked waypoints are kept; without it there is no Mark button.
  final JourneyStore? waypoints;

  /// Builds the list of past journeys, opened from the idle screen.
  final WidgetBuilder? historyBuilder;

  /// Builds the offline maps screen: areas kept for use without signal.
  final WidgetBuilder? offlineMapsBuilder;

  /// The offline areas saved, to say when the journey is inside one.
  final ValueListenable<List<OfflineMap>>? savedOffline;

  /// Finds places to go; without it there is no search.
  final PlaceSearch? places;

  /// Keeps destinations and plans the way there.
  final RoutePlanner? planner;

  /// The user's name and participant id; with [waypoints] (the store),
  /// enables groups.
  final Settings? settings;

  /// Keeps this phone present in its journey's group (G2).
  final GroupSync? group;

  /// Builds the invite-code scanner; injected so tests need no camera.
  final WidgetBuilder? scannerBuilder;

  /// Shares an invitation's text; injected so tests need no platform.
  final Future<void> Function(String text)? shareText;

  /// Switches the high-contrast look for bright daylight on or off.
  final VoidCallback? onToggleHighSun;

  final Future<void> Function(bool enabled)? onMapNetworkChanged;
  final DateTime Function() clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with WidgetsBindingObserver {
  late RecorderState _state = widget.recorder.state;
  late final StreamSubscription<RecorderState> _changes;
  Timer? _ticker;
  bool _busy = false;
  bool _detailsOpen = false;
  bool _visible = true;
  bool _sharingHeld = false;
  bool? _mapNetwork;
  Future<void> _networkChanges = Future.value();

  void _syncMapNetwork() {
    final enabled = _visible && _state is! Paused && _state is! Interrupted;
    if (_mapNetwork == enabled) return;
    _mapNetwork = enabled;
    _networkChanges = _networkChanges
        .then((_) async {
          await widget.onMapNetworkChanged?.call(enabled);
        })
        .catchError((Object _) {
          _tell('Map updates could not be stopped. Close and reopen Tripping.');
        });
  }

  /// The destination of the journey shown, and the way there.
  StreamSubscription<RouteRow?>? _routeWatch;
  int? _routeJourney;
  RouteRow? _route;
  RouteError? _routeWhy;
  bool _planning = false;

  /// The group of the journey shown (G1), and a join waiting for the
  /// journey it is starting.
  StreamSubscription<MembershipRow?>? _groupWatch;
  int? _groupJourney;
  MembershipRow? _membership;
  Invite? _pendingJoin;

  /// Progress along the way, from the newest live fix.
  RouteFollower? _follower;
  RouteProgress? _progress;
  DateTime? _followedFix;
  DateTime? _replannedAt;

  /// The direction of travel on an expedition, for "ahead" or "left".
  Course _course = Course();
  DateTime? _coursedFix;
  double? _heading;

  /// Android facts, refreshed on start and whenever the user comes back
  /// (they may have changed a setting meanwhile).
  bool? _notificationsShown;
  bool _restricted = false;
  List<LastExit> _exits = const [];

  /// Why the last start or resume could not go ahead, and how to retry it.
  LocationAccess? _refused;
  Future<LocationAccess> Function()? _retry;

  @override
  void initState() {
    super.initState();
    widget.settings?.identity.addListener(_identityChanged);
    _changes = widget.recorder.changes.listen((state) {
      if (_visible) {
        setState(() => _state = state);
      } else {
        _state = state;
      }
      _syncTicker();
      _syncMapNetwork();
      if (state is! Recording) widget.planner?.cancelPending();
      _followRoute(state);
      _followGroup(state);
      _share(state);
      _follow();
      _trackCourse();
    });
    _visible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _syncTicker();
    _syncMapNetwork();
    _followRoute(_state);
    _followGroup(_state);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshSystem());
    widget.system.linksArrive.addListener(_takeLink);
    _takeLink();
  }

  void _identityChanged() {
    if (!mounted) return;
    setState(() {});
    _share(_state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings?.identity.removeListener(_identityChanged);
    _ticker?.cancel();
    unawaited(_changes.cancel());
    unawaited(_routeWatch?.cancel());
    unawaited(_groupWatch?.cancel());
    widget.system.linksArrive.removeListener(_takeLink);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _syncTicker();
    _syncMapNetwork();
    if (_visible) {
      setState(() {});
      // Native Auth can re-arm an empty refresh task on foreground return.
      final state = _state;
      if (state is! Recording ||
          _sharingHeld ||
          widget.settings?.sharingPaused(state.journey.uuid) == true) {
        _suspendSharing();
      }
      unawaited(_refreshSystem());
      _takeLink();
    }
  }

  Future<void> _refreshSystem() async {
    final system = widget.system;
    final shown = await system.notificationsEnabled();
    final restricted = await system.isBackgroundRestricted();
    final exits = await system.recentExits();
    if (!mounted) return;
    setState(() {
      _notificationsShown = shown;
      _restricted = restricted;
      _exits = exits;
    });
  }

  /// Asks to show the recording notification before recording starts, at
  /// most as often as Android allows. A refusal does not stop recording.
  Future<void> _askForNotifications() async {
    if (_notificationsShown ?? false) return;
    final shown = await widget.system.requestNotifications();
    if (mounted) setState(() => _notificationsShown = shown);
  }

  /// Ticks once a second only while recording, for the clock and the age of
  /// the last fix.
  void _syncTicker() {
    if (_state is Recording && _visible) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _askFor(Future<LocationAccess> Function() command) async {
    setState(() {
      _busy = true;
      _refused = null;
    });
    try {
      await _askForNotifications();
      final access = await command();
      if (!mounted) return;
      setState(() {
        _refused = access == LocationAccess.granted ? null : access;
        _retry = command;
      });
    } catch (error) {
      _tell('Something went wrong: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() async {
    try {
      await widget.recorder.pause();
      widget.planner?.cancelPending();
      await widget.group?.suspend();
      await _networkChanges;
    } catch (error) {
      _tell('Could not pause: $error. Still recording.');
    }
  }

  Future<void> _end() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this journey?'),
        content: const Text('It stays saved on this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('End journey'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final last = await widget.recorder.end();
      if (last != null) {
        _tell(
          'Journey saved · ${kilometres(last.meters)} · '
          '${clockTime(last.elapsedAt(widget.clock()))}',
        );
      }
    } catch (error) {
      _tell('Could not end the journey: $error');
    }
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Watches the destination of the journey shown. A destination chosen
  /// before the start goes with the new journey.
  void _followRoute(RecorderState state) {
    final planner = widget.planner;
    if (planner == null) return;
    final journey = switch (state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey,
      Idle() => null,
    };
    if (journey?.id != _routeJourney) {
      _routeJourney = journey?.id;
      unawaited(_routeWatch?.cancel());
      _routeWatch = null;
      _route = null;
      _routeWhy = null;
      _follower = null;
      _progress = null;
      _followedFix = null;
      _replannedAt = null;
      _course = Course();
      _coursedFix = null;
      _heading = null;
      if (journey != null) {
        final pending = planner.pending.value;
        if (pending != null) {
          planner.pending.value = null;
          unawaited(planner.goTo(journey.id, pending));
        }
        _routeWatch = planner.watch(journey.id).listen((route) {
          if (!mounted) return;
          setState(() {
            _route = route;
            _follower = _followerFor(route);
            _progress = null;
            _followedFix = null;
          });
          _follow();
          _planIfDue();
        });
      }
    }
    _planIfDue();
  }

  /// On an expedition, the live fix the destination's direction is told
  /// from; null on the road, or without a live fix.
  static Fix? _compassFix(RecorderState state, DateTime now) => switch (state) {
    Recording(
      journey: JourneyRow(mode: JourneyMode.expedition),
      :final latestFix?,
      :final latestFixArrivedAt?,
    )
        when now.difference(latestFixArrivedAt) <= quietAfter =>
      latestFix,
    _ => null,
  };

  static RouteFollower? _followerFor(RouteRow? route) {
    final kind = route?.kind;
    final geometry = route?.geometry;
    if (route == null || kind == null || geometry == null) return null;
    return RouteFollower(
      points: decodePolyline(geometry),
      kind: kind,
      meters: route.meters ?? 0,
      seconds: route.seconds,
      destination: (route.latitude, route.longitude),
    );
  }

  /// Follows the newest live fix along the way. Off the road, or on a
  /// straight line for want of a connection, asks for a new way now and
  /// then.
  void _follow() {
    final follower = _follower;
    final state = _state;
    if (follower == null || state is! Recording) return;
    final fix = state.latestFix;
    if (fix == null || fix.time == _followedFix) return;
    _followedFix = fix.time;
    final progress = follower.update(fix);
    setState(() => _progress = progress);
    if (progress.arrived) return;
    final why = _routeWhy;
    final unconnected =
        follower.kind == RouteKind.straight && (why == null || why.offline);
    if (progress.offRoute || unconnected) _replan();
  }

  void _trackCourse() {
    final state = _state;
    if (state is! Recording) return;
    final fix = state.latestFix;
    if (fix == null || fix.time == _coursedFix) return;
    _coursedFix = fix.time;
    _heading = _course.update(fix);
  }

  /// A new way from here, keeping the old one if none comes. [asked] by
  /// the user goes ahead at once.
  void _replan({bool asked = false}) {
    final at = widget.clock();
    final last = _replannedAt;
    if (!asked && last != null && at.difference(last) < _replanEvery) return;
    _replannedAt = at;
    _planIfDue(again: true, keepOnFailure: true);
  }

  bool get _groups => widget.settings != null && widget.waypoints != null;

  /// Watches the group of the journey shown. A join chosen before the start
  /// goes with the new journey.
  void _followGroup(RecorderState state) {
    final store = widget.waypoints;
    if (store == null || !_groups) return;
    final journey = switch (state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey,
      Idle() => null,
    };
    if (journey?.id == _groupJourney) return;
    _groupJourney = journey?.id;
    unawaited(_groupWatch?.cancel());
    _groupWatch = null;
    final was = _membership;
    _membership = null;
    final group = widget.group;
    if (group != null) {
      // A journey in a group has ended: say so, and the inviter's ending
      // ends the group (D-037).
      unawaited(
        journey == null && was != null ? group.finish() : group.follow(null),
      );
    }
    if (journey == null) return;
    final join = _pendingJoin;
    _pendingJoin = null;
    if (join != null) unawaited(_saveJoin(journey, join));
    _groupWatch = store.watchMembership(journey.id).listen((membership) {
      if (mounted) setState(() => _membership = membership);
      _share(_state);
    });
  }

  /// Hands the group what there is to say: the journey's phase and its
  /// newest saved fix (never one not yet saved).
  void _share(RecorderState state) {
    final group = widget.group;
    if (group == null || _membership == null) return;
    final (journey, phase, progress) = switch (state) {
      Recording(:final journey, :final progress) => (
        journey,
        JourneyPhase.recording,
        progress,
      ),
      Paused(:final journey, :final progress) ||
      Interrupted(
        :final journey,
        :final progress,
      ) => (journey, JourneyPhase.paused, progress),
      Idle() => (null, null, null),
    };
    if (journey == null || phase == null || progress == null) return;
    if (state is! Recording ||
        _sharingHeld ||
        widget.settings?.sharingPaused(journey.uuid) == true) {
      _suspendSharing();
      return;
    }
    unawaited(group.follow(_membership));
    group.update(
      Shared(
        name: widget.settings?.name.value ?? 'Traveller',
        colour: widget.settings?.identity.value.colour ?? IdentityColour.clay,
        shape: widget.settings?.identity.value.shape ?? MarkerShape.tablet,
        phase: phase,
        mode: journey.mode,
        fix: progress.lastFix,
        fixArrivedAt: progress.lastFixArrivedAt,
      ),
    );
  }

  void _suspendSharing() {
    unawaited(
      widget.group?.suspend().catchError((Object _) {
        _tell(
          'Could not stop group sign-in. Close Tripping to finish pausing.',
        );
      }),
    );
  }

  Future<void> _toggleSharing() async {
    final state = _state;
    final settings = widget.settings;
    if (state is! Recording || settings == null) return;
    final paused =
        !(_sharingHeld || settings.sharingPaused(state.journey.uuid));
    _sharingHeld = true;
    // Withdrawal stops transport immediately, even if preference saving fails.
    if (paused) await widget.group?.suspend();
    try {
      await settings.setSharingPaused(state.journey.uuid, paused);
      _sharingHeld = false;
      if (!mounted) return;
      setState(() {});
      _share(_state);
    } on Object {
      _tell('Could not save the sharing choice. Group updates stay paused.');
    }
  }

  /// On a road journey following a road route, measures companions along
  /// it (G6); kept while the route is the same.
  Convoy? _convoy;
  String? _convoyGeometry;

  Convoy? _convoyFor(RecorderState state, RouteRow? route) {
    final road = switch (state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey.mode == JourneyMode.road,
      Idle() => false,
    };
    final geometry = route?.geometry;
    if (!road || route?.kind != RouteKind.road || geometry == null) {
      return null;
    }
    if (geometry != _convoyGeometry) {
      _convoyGeometry = geometry;
      _convoy = Convoy(decodePolyline(geometry));
    }
    return _convoy;
  }

  /// Leaves the group, inviter or not: this phone stops sharing, the group
  /// and the journey go on (D-037).
  Future<void> _leaveGroup() async {
    final membership = _membership;
    final store = widget.waypoints;
    if (membership == null || store == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the group?'),
        content: const Text(
          'You stop sharing your position with the group. The group and '
          'your journey go on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (!(sure ?? false)) return;
    // Sharing stops now. If the relay could not confirm removing this
    // phone's last position, it is removed at the next connection.
    final unconfirmed = await widget.group?.leave();
    if (unconfirmed != null) {
      await widget.settings?.addPendingLeave(unconfirmed);
      _tell(
        'Left the group. Your last position is removed from it as soon as '
        'Tripping is online.',
      );
    }
    await store.deleteMembership(membership.journeyId);
  }

  Future<void> _saveJoin(JourneyRow journey, Invite invite) async {
    if (invite.groupId == journey.uuid) {
      _tell('That is your own group.');
      return;
    }
    try {
      await widget.waypoints!.saveMembership(
        journey.id,
        groupId: invite.groupId,
        secret: invite.secret,
        role: GroupRole.member,
        hostName: invite.hostName,
        at: widget.clock(),
      );
    } on StateError {
      _tell('This journey is already in a group.');
    }
  }

  /// Hands an invitation link that opened Tripping to the join screen.
  void _takeLink() {
    if (!_groups) return;
    unawaited(() async {
      final link = await widget.system.takeOpenedLink();
      final invite = Invite.find(link ?? '');
      if (invite != null && mounted) await _join(invite);
    }());
  }

  /// Makes the journey's group (or reuses it) and shows its invitation.
  Future<void> _invite() async {
    final store = widget.waypoints;
    final settings = widget.settings;
    final journey = switch (_state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey,
      Idle() => null,
    };
    if (store == null || settings == null || journey == null) return;
    final name = await nameForGroups(context, settings);
    if (name == null || !mounted) return;
    await settings.participantId();
    var membership = await store.membershipOf(journey.id);
    if (membership == null) {
      final made = Invite.create(
        journey.uuid,
        name,
        colour: settings.identity.value.colour,
        shape: settings.identity.value.shape,
      );
      await store.saveMembership(
        journey.id,
        groupId: made.groupId,
        secret: made.secret,
        role: GroupRole.creator,
        at: widget.clock(),
      );
      membership = await store.membershipOf(journey.id);
    }
    if (membership == null || !mounted) return;
    final invite = Invite(
      groupId: membership.groupId,
      secret: membership.secret,
      hostName: name,
      colour: settings.identity.value.colour,
      shape: settings.identity.value.shape,
    );
    _open((_) => InviteScreen(invite: invite, share: widget.shareText));
  }

  /// Finds an invitation (or takes [from]) and joins it: with the journey
  /// under way, or by starting one.
  Future<void> _join([Invite? from]) async {
    final settings = widget.settings;
    if (settings == null || !_groups) return;
    final name = await nameForGroups(context, settings);
    if (name == null || !mounted) return;
    await settings.participantId();
    if (!mounted) return;
    final state = _state;
    final journey = switch (state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey,
      Idle() => null,
    };
    final choice = await Navigator.of(context).push<JoinChoice>(
      MaterialPageRoute(
        builder: (_) => JoinScreen(
          place: journey == null
              ? JoinPlace.startJourney
              : _membership == null
              ? JoinPlace.thisJourney
              : JoinPlace.alreadyInGroup,
          invite: from,
          scannerBuilder: widget.scannerBuilder,
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final start = choice.start;
    if (journey != null) {
      await _saveJoin(journey, choice.invite);
    } else if (start != null) {
      _pendingJoin = choice.invite;
      await _askFor(() => widget.recorder.start(start));
      // Asked of the recorder: the screen may hear of the start later.
      if (widget.recorder.state is Idle) _pendingJoin = null;
    }
  }

  /// Plans the way once there is a destination and a live fix to start
  /// from; [again] plans anew (after a straight line, say).
  void _planIfDue({bool again = false, bool keepOnFailure = false}) {
    final planner = widget.planner;
    final route = _route;
    final state = _state;
    if (planner == null || route == null || _planning) return;
    if (route.kind != null && !again) return;
    if (state is! Recording) return;
    final fix = state.latestFix;
    if (fix == null) return;
    _planning = true;
    if (mounted) setState(() {});
    unawaited(
      planner
          .plan(
            state.journey.id,
            (fix.latitude, fix.longitude),
            state.journey.mode,
            keepOnFailure: keepOnFailure,
          )
          .then((why) {
            if (mounted) setState(() => _routeWhy = why);
          })
          .whenComplete(() {
            _planning = false;
            if (mounted) setState(() {});
          }),
    );
  }

  /// Asks for a place to go; null when the user backs out.
  Future<Place?> _searchPlace() async {
    final places = widget.places;
    final planner = widget.planner;
    if (places == null || planner == null) return null;
    final fix =
        switch (_state) {
          Recording(:final latestFix?) => latestFix,
          Recording(:final progress) ||
          Paused(:final progress) ||
          Interrupted(:final progress) => progress.lastFix,
          Idle() => null,
        } ??
        await widget.location.lastKnown();
    if (!mounted) return null;
    return Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          search: places,
          recent: planner.recent,
          near: fix == null ? null : (fix.latitude, fix.longitude),
          distances:
              fix != null &&
              widget.clock().difference(fix.time) <= _nearFreshFor,
        ),
      ),
    );
  }

  Future<void> _chooseDestination() async {
    final planner = widget.planner;
    final place = await _searchPlace();
    if (place == null || planner == null || !mounted) return;
    final journey = _routeJourney;
    if (journey == null) {
      planner.pending.value = place;
    } else {
      setState(() => _routeWhy = null);
      await planner.goTo(journey, place);
    }
  }

  void _open(WidgetBuilder screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: screen));

  /// Saves where the phone is the moment the user asks, then offers to name
  /// it. Says so when the newest fix is not a live one.
  Future<void> _mark(Recording state) async {
    final store = widget.waypoints;
    final fix = state.latestFix;
    final arrived = state.latestFixArrivedAt;
    if (store == null || fix == null) return;
    final now = widget.clock();
    final waypoint = await store.addWaypoint(
      state.journey.id,
      kind: WaypointKind.marked,
      at: now,
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracy: fix.accuracy,
      altitude: fix.altitude,
      fixTime: fix.time,
    );
    final quiet = arrived == null ? null : now.difference(arrived);
    if (!mounted) return;
    await showWaypointSheet(
      context,
      store: store,
      waypoint: waypoint,
      warning: quiet != null && quiet > quietAfter
          ? 'Marked at the last position known, ${age(quiet)} ago.'
          : null,
    );
  }

  String _routeCaption(RouteRow route) {
    if (_progress?.arrived == true) return 'Arrived';
    if (_progress?.offRoute == true) return 'Off route';
    if (route.kind == null) {
      if (_planning) return 'Finding a way…';
      return _routeWhy == null ? 'Destination selected' : 'Route unavailable';
    }
    if (route.kind == RouteKind.straight) return 'Direction only';
    final progress = _progress;
    if (progress != null) return '${kilometres(progress.metersLeft)} to go';
    return _planning ? 'Finding a way…' : 'Planned way';
  }

  void _toggleDetails() => setState(() => _detailsOpen = !_detailsOpen);

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final state = _state;
    final active = state is! Idle;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: widget.mapBuilder(state, now)),
                if (widget.waypoints != null && state is Recording)
                  Positioned(
                    left: Space.gutter,
                    bottom: Space.lg,
                    child: MapChrome(
                      child: TextButton.icon(
                        onPressed: state.latestFix == null
                            ? null
                            : () => _mark(state),
                        icon: const Icon(
                          Icons.add_location_alt_outlined,
                          size: 22,
                        ),
                        label: const Text('Mark'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(96, Touch.min),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.md,
                        Space.gutter,
                        0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: MapChrome(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.lg,
                                  vertical: Space.md,
                                ),
                                child: Header(state: state),
                              ),
                            ),
                          ),
                          if (widget.settings case final settings?) ...[
                            const SizedBox(width: Space.sm),
                            Tooltip(
                              message: 'Your map identity',
                              child: MapChrome(
                                child: IconButton(
                                  onPressed: () => _open(
                                    (_) => IdentityScreen(settings: settings),
                                  ),
                                  icon: ExcludeSemantics(
                                    child: IdentityMarker(
                                      identity: settings.identity.value,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (widget.onToggleHighSun case final toggle?) ...[
                            const SizedBox(width: Space.sm),
                            HighSunButton(onPressed: toggle),
                          ],
                          const SizedBox(width: Space.sm),
                          MapChrome(
                            child: PopupMenuButton<String>(
                              tooltip: 'Map options',
                              icon: const Icon(Icons.more_horiz_rounded),
                              onSelected: (value) {
                                switch (value) {
                                  case 'key':
                                    showMapKey(
                                      context,
                                      identity: widget.settings?.identity.value,
                                    );
                                  case 'offline':
                                    final builder = widget.offlineMapsBuilder;
                                    if (builder != null) _open(builder);
                                  case 'details':
                                    _toggleDetails();
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'key',
                                  child: ListTile(
                                    leading: Icon(Icons.map_outlined),
                                    title: Text('Map symbols'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                if (widget.offlineMapsBuilder != null && active)
                                  const PopupMenuItem(
                                    value: 'offline',
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.download_for_offline_outlined,
                                      ),
                                      title: Text('Offline maps'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                if (active)
                                  const PopupMenuItem(
                                    value: 'details',
                                    child: ListTile(
                                      leading: Icon(Icons.tune_rounded),
                                      title: Text('Journey details'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SheetSurface(
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .6,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (active)
                        GestureDetector(
                          onVerticalDragEnd: (drag) {
                            final speed = drag.primaryVelocity ?? 0;
                            if (speed.abs() > 80) {
                              setState(() => _detailsOpen = speed < 0);
                            }
                          },
                          child: Tooltip(
                            message: 'Journey details',
                            child: Semantics(
                              button: true,
                              expanded: _detailsOpen,
                              label: 'Journey details',
                              child: InkWell(
                                onTap: _toggleDetails,
                                child: SizedBox(
                                  height: 48,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: scheme.outlineVariant,
                                          borderRadius: BorderRadius.circular(
                                            Space.xs,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 20,
                                        child: Icon(
                                          _detailsOpen
                                              ? Icons.expand_more_rounded
                                              : Icons.expand_less_rounded,
                                          color: scheme.onSurfaceVariant,
                                          size: 22,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          active ? 0 : 20,
                          20,
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            switch (state) {
                              Idle() => const Welcome(),
                              _ => Readout(state: state, now: now),
                            },
                            if (active &&
                                !_detailsOpen &&
                                _route == null &&
                                widget.planner != null &&
                                widget.places != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: OutlinedButton.icon(
                                  onPressed: _chooseDestination,
                                  icon: const Icon(Icons.search_rounded),
                                  label: const Text('Where to?'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    alignment: Alignment.centerLeft,
                                  ),
                                ),
                              ),
                            if (active && !_detailsOpen)
                              if (_route case final route?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: InkWell(
                                    onTap: _toggleDetails,
                                    borderRadius: Corner.smallRadius,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            route.kind == RouteKind.straight
                                                ? Icons.near_me_outlined
                                                : Icons.place_rounded,
                                            color: scheme.secondary,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  route.destination,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                Text(
                                                  _routeCaption(route),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color:
                                                            _progress
                                                                    ?.offRoute ==
                                                                true
                                                            ? warningColor(
                                                                context,
                                                              )
                                                            : scheme
                                                                  .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            if (!active || _detailsOpen) ...[
                              if (widget.planner case final planner?
                                  when widget.places != null)
                                switch (state) {
                                  Idle() => ValueListenableBuilder(
                                    valueListenable: planner.pending,
                                    builder: (context, pending, _) =>
                                        NextDestination(
                                          pending: pending,
                                          onSearch: _chooseDestination,
                                          onClear: () =>
                                              planner.pending.value = null,
                                        ),
                                  ),
                                  _ => DestinationLine(
                                    mode: switch (state) {
                                      Recording(:final journey) ||
                                      Paused(:final journey) ||
                                      Interrupted(
                                        :final journey,
                                      ) => journey.mode,
                                      Idle() => JourneyMode.road,
                                    },
                                    route: _route,
                                    why: _routeWhy,
                                    planning: _planning,
                                    progress: _progress,
                                    now: now,
                                    here: _compassFix(state, now),
                                    heading: _heading,
                                    onSearch: _chooseDestination,
                                    onClear: () {
                                      final journey = _routeJourney;
                                      if (journey != null) {
                                        unawaited(planner.clear(journey));
                                      }
                                    },
                                    onRetry: () => _replan(asked: true),
                                  ),
                                },
                              if (_groups && state is! Idle)
                                GroupLine(
                                  membership: _membership,
                                  paused: state is! Recording,
                                  sharingPaused: switch (state) {
                                    Recording(:final journey) =>
                                      widget.settings?.sharingPaused(
                                            journey.uuid,
                                          ) ??
                                          false,
                                    _ => false,
                                  },
                                  onToggleSharing: state is Recording
                                      ? _toggleSharing
                                      : null,
                                  status: widget.group?.status,
                                  now: now,
                                  here: switch (state) {
                                    Recording(:final latestFix?) => latestFix,
                                    Recording(:final progress) ||
                                    Paused(:final progress) ||
                                    Interrupted(
                                      :final progress,
                                    ) => progress.lastFix,
                                    Idle() => null,
                                  },
                                  onLeave: _leaveGroup,
                                  convoy: _convoyFor(state, _route),
                                  onInvite: _invite,
                                  onJoin: _join,
                                ),

                              if (widget.savedOffline case final saved?)
                                SavedHere(state: state, saved: saved),
                              Coordinates(state: state, now: now),
                            ],
                            if (active && !_detailsOpen && _groups)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _toggleDetails,
                                  icon: const Icon(
                                    Icons.people_outline_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    state is Recording
                                        ? 'Companions'
                                        : 'Companions · sharing paused',
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            StatusLine(
                              state: state,
                              now: now,
                              exits: _exits,
                              compact: active && !_detailsOpen,
                              onOpenLocationSettings: () => widget.location
                                  .openSettingsFor(LocationAccess.serviceOff),
                              onOpenAppSettings: widget.system.openAppSettings,
                            ),
                            SystemNotes(
                              state: state,
                              restricted: _restricted,
                              notificationsShown: _notificationsShown,
                              onOpenAppSettings: widget.system.openAppSettings,
                            ),
                            if (_refused case final problem?)
                              AccessProblem(
                                problem: problem,
                                onRetry: _retry == null
                                    ? null
                                    : () => _askFor(_retry!),
                                onOpenSettings: () =>
                                    widget.location.openSettingsFor(problem),
                              ),
                            const SizedBox(height: 12),
                            ..._actions(state),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(RecorderState state) {
    final recorder = widget.recorder;
    final enabled = !_busy;
    return switch (state) {
      Idle() => [
        ActionPair(
          ModeCard(
            label: 'Road journey',
            icon: Icons.directions_car_outlined,
            art: ModeArt.road,
            onPressed: enabled
                ? () => _askFor(() => recorder.start(JourneyMode.road))
                : null,
          ),
          ModeCard(
            label: 'Expedition',
            icon: Icons.hiking,
            art: ModeArt.expedition,
            onPressed: enabled
                ? () => _askFor(() => recorder.start(JourneyMode.expedition))
                : null,
          ),
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (widget.historyBuilder case final history?)
              TextButton.icon(
                onPressed: () => _open(history),
                icon: const Icon(Icons.history),
                label: const Text('Past journeys'),
              ),
            if (widget.offlineMapsBuilder case final offline?)
              TextButton.icon(
                onPressed: () => _open(offline),
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('Offline maps'),
              ),
            if (_groups)
              TextButton.icon(
                onPressed: _join,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Join a group'),
              ),
          ],
        ),
      ],
      Recording() => [
        ActionPair(
          FilledButton.icon(
            onPressed: enabled ? _pause : null,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
          OutlinedButton(
            onPressed: enabled ? _end : null,
            child: const Text('End journey'),
          ),
        ),
      ],
      Paused() || Interrupted() => [
        ActionPair(
          FilledButton.icon(
            onPressed: enabled ? () => _askFor(recorder.resume) : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          ),
          OutlinedButton(
            onPressed: enabled ? _end : null,
            child: const Text('End journey'),
          ),
        ),
      ],
    };
  }
}
