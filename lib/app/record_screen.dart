import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../journey/geo.dart';
import '../journey/journey.dart';
import '../journey/journey_store.dart';
import '../map/offline_area.dart';
import '../map/offline_maps.dart';
import '../places/place.dart';
import '../places/place_search.dart';
import '../places/polyline.dart';
import '../routing/route_planner.dart';
import '../routing/route_progress.dart';
import '../routing/router.dart';
import '../recording/course.dart';
import '../recording/location_source.dart';
import '../recording/recorder.dart';
import '../recording/track_policy.dart';
import '../group/convoy.dart';
import '../group/group_sync.dart';
import '../group/invite.dart';
import '../group/identity.dart';
import '../group/sharing.dart';
import 'figure.dart';
import 'format.dart';
import 'group_screens.dart';
import 'settings.dart';
import 'identity_screen.dart';
import 'identity_marker.dart';
import 'system_access.dart';
import 'search_screen.dart';
import 'theme.dart';
import 'waypoint_sheet.dart';

/// Seconds without a fix before the screen says so.
const _quietAfter = Duration(seconds: 15);

/// Seconds after starting without any fix before the screen says so.
const _noFixAfter = Duration(seconds: 30);

/// How long a fix's speed still counts as the speed now.
const _speedFreshFor = Duration(seconds: 5);

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
        when now.difference(latestFixArrivedAt) <= _quietAfter =>
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
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (!(sure ?? false)) return;
    await widget.group?.leave();
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
      warning: quiet != null && quiet > _quietAfter
          ? 'Marked at the last position known, ${age(quiet)} ago.'
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final state = _state;
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
                    left: 16,
                    bottom: 16,
                    child: FloatingActionButton.extended(
                      heroTag: null,
                      onPressed: state.latestFix == null
                          ? null
                          : () => _mark(state),
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Mark'),
                    ),
                  ),
                if (widget.settings case final settings?)
                  Positioned(
                    top: 64,
                    right: 16,
                    child: SafeArea(
                      bottom: false,
                      child: _RoundButton(
                        onPressed: () =>
                            _open((_) => IdentityScreen(settings: settings)),
                        icon: Icons.person_outline,
                        tooltip: 'Your map identity',
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: _Header(state: state),
                            ),
                          ),
                          if (widget.onToggleHighSun case final toggle?) ...[
                            const SizedBox(width: 8),
                            _HighSunButton(onPressed: toggle),
                          ],
                          // Reachable during a trip too: an area can be
                          // saved while there is still a signal.
                          if (widget.offlineMapsBuilder case final offline?
                              when state is! Idle) ...[
                            const SizedBox(width: 8),
                            _RoundButton(
                              onPressed: () => _open(offline),
                              icon: Icons.download_for_offline_outlined,
                              tooltip: 'Offline maps',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The panel holds everything that is not the map. It scrolls rather
          // than overflow when the text is large.
          Material(
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      switch (state) {
                        Idle() => const _Welcome(),
                        Recording() ||
                        Paused() ||
                        Interrupted() => _Readout(state: state, now: now),
                      },
                      if (widget.planner case final planner?
                          when widget.places != null)
                        switch (state) {
                          Idle() => ValueListenableBuilder(
                            valueListenable: planner.pending,
                            builder: (context, pending, _) => _NextDestination(
                              pending: pending,
                              onSearch: _chooseDestination,
                              onClear: () => planner.pending.value = null,
                            ),
                          ),
                          _ => _DestinationLine(
                            mode: switch (state) {
                              Recording(:final journey) ||
                              Paused(:final journey) ||
                              Interrupted(:final journey) => journey.mode,
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
                        _GroupLine(
                          membership: _membership,
                          paused: state is! Recording,
                          sharingPaused: switch (state) {
                            Recording(:final journey) =>
                              widget.settings?.sharingPaused(journey.uuid) ??
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
                            Interrupted(:final progress) => progress.lastFix,
                            Idle() => null,
                          },
                          onLeave: _leaveGroup,
                          convoy: _convoyFor(state, _route),
                          onInvite: _invite,
                          onJoin: _join,
                        ),
                      const SizedBox(height: 12),
                      _StatusLine(
                        state: state,
                        now: now,
                        exits: _exits,
                        onOpenLocationSettings: () => widget.location
                            .openSettingsFor(LocationAccess.serviceOff),
                        onOpenAppSettings: widget.system.openAppSettings,
                      ),
                      if (widget.savedOffline case final saved?)
                        _SavedHere(state: state, saved: saved),
                      _Coordinates(state: state, now: now),
                      _SystemNotes(
                        state: state,
                        restricted: _restricted,
                        notificationsShown: _notificationsShown,
                        onOpenAppSettings: widget.system.openAppSettings,
                      ),
                      const SizedBox(height: 12),
                      if (_refused case final problem?)
                        _AccessProblem(
                          problem: problem,
                          onRetry: _retry == null
                              ? null
                              : () => _askFor(_retry!),
                          onOpenSettings: () =>
                              widget.location.openSettingsFor(problem),
                        ),
                      ..._actions(state),
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
        FilledButton.icon(
          onPressed: enabled
              ? () => _askFor(() => recorder.start(JourneyMode.road))
              : null,
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('Road journey'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: enabled
              ? () => _askFor(() => recorder.start(JourneyMode.expedition))
              : null,
          icon: const Icon(Icons.hiking),
          label: const Text('Expedition'),
        ),
        const SizedBox(height: 4),
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
        _ActionPair(
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
        _ActionPair(
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

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final RecorderState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state) {
      Idle() => ('Tripping', scheme.onSurface),
      Recording(:final journey) => (
        'Recording · ${modeName(journey.mode)}',
        scheme.primary,
      ),
      Paused(:final journey) => (
        'Paused · ${modeName(journey.mode)}',
        scheme.onSurfaceVariant,
      ),
      Interrupted(:final journey) => (
        'Stopped · ${modeName(journey.mode)}',
        warningColor(context),
      ),
    };
    return Row(
      children: [
        if (state is Recording) ...[
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Two actions side by side, leaving more of the screen to the map; one
/// above the other when large text would not fit.
class _ActionPair extends StatelessWidget {
  const _ActionPair(this.first, this.second);

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(18) > 22) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 12), second],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

/// A small round button over the map, like the header.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
    shape: const CircleBorder(),
    child: IconButton(onPressed: onPressed, icon: Icon(icon), tooltip: tooltip),
  );
}

/// Switches the high-contrast look for direct sunlight; filled while on.
class _HighSunButton extends StatelessWidget {
  const _HighSunButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = lookOf(context).look == Look.highSun;
    return Material(
      color: scheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        isSelected: on,
        icon: const Icon(Icons.wb_sunny_outlined),
        selectedIcon: const Icon(Icons.wb_sunny),
        tooltip: on ? 'High-sun mode on' : 'High-sun mode',
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where to?', style: text.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Record a road journey or an expedition. Everything stays on this '
          'phone, and no internet is needed.',
          style: text.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The numbers that matter for the kind of journey: on the road, speed
/// first; on an expedition, time and moving time.
class _Readout extends StatelessWidget {
  const _Readout({required this.state, required this.now});

  final RecorderState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (journey, progress) = switch (state) {
      Recording(:final journey, :final progress) ||
      Paused(:final journey, :final progress) ||
      Interrupted(:final journey, :final progress) => (journey, progress),
      Idle() => throw StateError('No journey to read out'),
    };
    final time = Figure(
      value: clockTime(progress.elapsedAt(now)),
      label: 'Time',
    );
    final distance = Figure(
      value: kilometres(progress.meters),
      label: 'Distance',
    );
    final row = Row(
      children: [
        for (final figure in switch (journey.mode) {
          JourneyMode.road => [
            Figure(value: speedText(_freshSpeed()), label: 'Speed'),
            distance,
            time,
          ],
          JourneyMode.expedition => [
            time,
            distance,
            Figure(value: clockTime(progress.movingTime), label: 'Moving'),
          ],
        })
          Expanded(child: figure),
      ],
    );
    final (climb, descent) = (progress.climb, progress.descent);
    if (journey.mode != JourneyMode.expedition ||
        climb == null ||
        descent == null) {
      return row;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 4),
        Text(
          'Climb ${climbText(climb)} · Descent ${climbText(descent)}',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// The GPS's own speed from a fix at most a few seconds old; anything
  /// older is not the speed now.
  double? _freshSpeed() => switch (state) {
    Recording(:final latestFix?, :final latestFixArrivedAt?)
        when now.difference(latestFixArrivedAt) <= _speedFreshFor =>
      latestFix.speed,
    _ => null,
  };
}

/// Before a trip: where it will go, or a way to choose.
class _NextDestination extends StatelessWidget {
  const _NextDestination({
    required this.pending,
    required this.onSearch,
    required this.onClear,
  });

  final Place? pending;
  final VoidCallback onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final pending = this.pending;
    if (pending == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Search a place'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _DestinationCard(
        title: 'To ${pending.name}',
        subtitle: pending.detail ?? 'The way is planned once you start.',
        onSearch: onSearch,
        onClear: onClear,
      ),
    );
  }
}

/// During a trip: where it is going and how far, in plain words. A straight
/// line says it is one.
class _DestinationLine extends StatelessWidget {
  const _DestinationLine({
    required this.mode,
    required this.route,
    required this.why,
    required this.planning,
    required this.progress,
    required this.now,
    required this.here,
    required this.heading,
    required this.onSearch,
    required this.onClear,
    required this.onRetry,
  });

  final JourneyMode mode;
  final RouteRow? route;
  final RouteError? why;
  final bool planning;

  /// How far along the way, while recording with a live fix.
  final RouteProgress? progress;
  final DateTime now;

  /// On an expedition, the live fix to tell the destination's direction
  /// from.
  final Fix? here;

  /// The direction of travel, when known (see [Course]).
  final double? heading;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final route = this.route;
    if (route == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Set a destination'),
        ),
      );
    }
    final progress = this.progress;
    final meters = progress?.metersLeft ?? route.meters ?? 0;
    final seconds = progress == null ? route.seconds : progress.secondsLeft;
    final why = this.why;
    final (subtitle, retry) = switch ((route.kind, progress)) {
      (_, RouteProgress(arrived: true)) => ('You have arrived.', false),
      (RouteKind.road, RouteProgress(offRoute: true)) => (
        [
          'Off the route · ${kilometres(meters)} away in a straight line.',
          if (planning) 'Finding a new way…' else if (why != null) why.message,
        ].join(' '),
        !planning && why != null,
      ),
      _ when planning && route.kind == null => ('Planning the way…', false),
      (null, _) => ('The way is planned at the first GPS fix.', false),
      (RouteKind.road, null) => (
        '${kilometres(meters)} ${wayWords(mode)}'
            '${seconds == null ? '' : ' · ${_roughly(seconds)}'}',
        false,
      ),
      (RouteKind.road, _) => (
        '${kilometres(meters)} to go ${wayWords(mode)}'
            '${seconds == null ? '' : ' · ${_roughly(seconds)}, arriving '
                      'around ${_clock(context, seconds)}'}',
        false,
      ),
      (RouteKind.straight, _) => (
        '${kilometres(meters)} in a straight line, ${notAWay(mode)}. '
            '${planning ? 'Looking for a way…' : why?.message ?? 'No way was found.'}',
        !planning,
      ),
    };
    final compass = _compass(route);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _DestinationCard(
        title: 'To ${route.destination}',
        subtitle: compass == null ? subtitle : '$subtitle\n$compass',
        onSearch: onSearch,
        onClear: onClear,
        action: retry ? (label: 'Try again', onPressed: onRetry) : null,
      ),
    );
  }

  /// "1.24 km NW (312°) in a straight line · ahead left": the direction
  /// as the crow flies, and, while moving, where that is from the way the
  /// walker is going. Off-trail, this is what finds the way.
  String? _compass(RouteRow route) {
    final here = this.here;
    if (here == null || (progress?.arrived ?? false)) return null;
    final bearing = bearingBetween(
      here.latitude,
      here.longitude,
      route.latitude,
      route.longitude,
    );
    final meters = metersBetween(
      here.latitude,
      here.longitude,
      route.latitude,
      route.longitude,
    );
    final heading = this.heading;
    return [
      '${kilometres(meters)} ${compassPoint(bearing)} '
          '(${bearing.round() % 360}°) in a straight line',
      if (heading != null) relativeDirection(bearing, heading),
    ].join(' · ');
  }

  /// The time of day [seconds] from [now]: an estimate, said as one.
  String _clock(BuildContext context, double seconds) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(
          now.add(Duration(seconds: seconds.round())).toLocal(),
        ),
      );

  /// "about 25 min", "about 2 h 10 min": a service's estimate, not a
  /// promise.
  static String _roughly(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return 'about $minutes min';
    return 'about ${minutes ~/ 60} h ${minutes % 60} min';
  }
}

/// The journey's group, in plain words: reachable or not, and each
/// companion's position with its age, from their newest saved fix. An old
/// position is said to be old, never shown as current.
class _GroupLine extends StatelessWidget {
  const _GroupLine({
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

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.title,
    required this.subtitle,
    required this.onSearch,
    required this.onClear,
    this.action,
  });

  final String title;
  final String subtitle;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final _Action? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.flag_circle_outlined, color: scheme.secondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              Text(
                subtitle,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action case final action?)
                TextButton(
                  onPressed: action.onPressed,
                  child: Text(action.label),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onSearch,
          icon: const Icon(Icons.edit_location_alt_outlined),
          tooltip: 'Change destination',
        ),
        IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.close),
          tooltip: 'No destination',
        ),
      ],
    );
  }
}

/// Says so when the journey is inside an area saved for offline use: the
/// map there keeps working without signal.
class _SavedHere extends StatelessWidget {
  const _SavedHere({required this.state, required this.saved});

  final RecorderState state;
  final ValueListenable<List<OfflineMap>> saved;

  @override
  Widget build(BuildContext context) {
    final fix = switch (state) {
      Recording(:final latestFix?) => latestFix,
      Recording(:final progress) ||
      Paused(:final progress) ||
      Interrupted(:final progress) => progress.lastFix,
      Idle() => null,
    };
    if (fix == null) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: saved,
      builder: (context, areas, _) {
        final inside = areas.any(
          (area) =>
              area.complete && covers(area.area, fix.latitude, fix.longitude),
        );
        if (!inside) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(
                Icons.offline_pin_outlined,
                size: 18,
                color: scheme.tertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Offline map saved for this area',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// On an expedition, the position as coordinates, on demand: to tell
/// someone where you are, or to check a map. Says when it is not live.
class _Coordinates extends StatefulWidget {
  const _Coordinates({required this.state, required this.now});

  final RecorderState state;
  final DateTime now;

  @override
  State<_Coordinates> createState() => _CoordinatesState();
}

class _CoordinatesState extends State<_Coordinates> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final (fix, live) = switch (widget.state) {
      Recording(
        journey: JourneyRow(mode: JourneyMode.expedition),
        :final latestFix?,
        :final latestFixArrivedAt?,
      ) =>
        (latestFix, widget.now.difference(latestFixArrivedAt) <= _quietAfter),
      Recording(
        journey: JourneyRow(mode: JourneyMode.expedition),
        :final progress,
      ) ||
      Paused(
        journey: JourneyRow(mode: JourneyMode.expedition),
        :final progress,
      ) ||
      Interrupted(
        journey: JourneyRow(mode: JourneyMode.expedition),
        :final progress,
      ) => (progress.lastFix, false),
      _ => (null, false),
    };
    if (fix == null) return const SizedBox.shrink();
    if (!_shown) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _shown = true),
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('Show coordinates'),
        ),
      );
    }
    final text = coordinatesText(fix.latitude, fix.longitude);
    final accuracy = fix.accuracy;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _shown = false),
            child: Text(
              [
                if (!live) 'Last known:',
                text,
                if (accuracy != null) '±${accuracy.round()} m',
                // As the GPS reports it; GPS height is rougher than position.
                if (fix.altitude case final altitude?)
                  '· altitude ${altitude.round()} m'
                      '${switch (fix.altitudeAccuracy) {
                        final vertical? => ' ±${vertical.round()} m',
                        null => '',
                      }}',
              ].join(' '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: live ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text:
                    '${fix.latitude.toStringAsFixed(5)}, '
                    '${fix.longitude.toStringAsFixed(5)}',
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Coordinates copied')),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 20),
          tooltip: 'Copy coordinates',
        ),
      ],
    );
  }
}

typedef _Action = ({String label, VoidCallback onPressed});

/// One line about the GPS, saving or an interruption, in plain words, with
/// at most one action. Amber when something needs attention.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.state,
    required this.now,
    required this.exits,
    required this.onOpenLocationSettings,
    required this.onOpenAppSettings,
  });

  final RecorderState state;
  final DateTime now;

  /// Why recent processes ended, newest first, as Android recorded it.
  final List<LastExit> exits;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final (message, needsAttention, action) = switch (state) {
      Idle() => (null, false, null),
      final Recording recording => _recordingStatus(recording),
      Paused() => (
        'Paused. Recording and group updates are stopped until you resume.',
        false,
        null,
      ),
      Interrupted(:final stoppedAt) => _interruption(context, stoppedAt),
    };
    if (message == null) return const SizedBox.shrink();
    final color = needsAttention
        ? warningColor(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
        ),
        if (action != null)
          TextButton(onPressed: action.onPressed, child: Text(action.label)),
      ],
    );
  }

  (String, bool, _Action?) _recordingStatus(Recording state) {
    if (state.saveError != null) {
      return (
        'Can’t save to this phone. Positions are not being recorded.',
        true,
        null,
      );
    }
    final problem = state.locationProblem;
    if (problem is LocationUnavailable &&
        problem.reason == LocationAccess.serviceOff) {
      return (
        'Location is off. Still recording — turn it on to continue the track.',
        true,
        (label: 'Turn on location', onPressed: onOpenLocationSettings),
      );
    }
    if (problem != null) {
      return (
        'Location stopped. Still recording; the track resumes when it '
            'returns.',
        true,
        null,
      );
    }
    final fix = state.latestFix;
    final arrived = state.latestFixArrivedAt;
    if (fix == null || arrived == null) {
      // A start that fails inside the platform never reports an error, so
      // waiting too long is itself the signal (D-017).
      final since = state.progress.openSince;
      final waited = since == null ? Duration.zero : now.difference(since);
      if (waited > _noFixAfter) {
        return (
          'No GPS fix yet after ${age(waited)}. Fixes take longer indoors; '
              'check that location is on.',
          true,
          null,
        );
      }
      return ('Waiting for GPS…', false, null);
    }
    final quiet = now.difference(arrived);
    if (quiet > _quietAfter) {
      return ('No GPS fix for ${age(quiet)}', true, null);
    }
    final accuracy = fix.accuracy;
    final ceiling = TrackPolicy.of(state.journey.mode).maxAccuracy;
    if (accuracy == null) return ('GPS fix, accuracy unknown', false, null);
    if (accuracy > ceiling) {
      return (
        'Location approximate (±${accuracy.round()} m), not added to the '
            'track',
        true,
        null,
      );
    }
    return ('GPS ±${accuracy.round()} m', false, null);
  }

  /// Names the real cause when Android recorded one, and offers battery
  /// settings only when battery management may be to blame.
  (String, bool, _Action?) _interruption(
    BuildContext context,
    DateTime stoppedAt,
  ) {
    final time = timeOfDay(context, stoppedAt);
    // The process that ended the recording is the first to exit after the
    // last saved fix; later exits (an update, a crash days later) are not
    // the cause. The fix carries GPS time, so allow some clock skew.
    final candidates = [
      for (final exit in exits)
        if (!exit.at.isBefore(stoppedAt.subtract(const Duration(minutes: 2))))
          exit,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final cause = candidates.firstOrNull?.cause;
    const lost = 'so nothing after that was recorded.';
    final battery = (label: 'Battery settings', onPressed: onOpenAppSettings);
    return switch (cause) {
      ExitCause.user => (
        'Recording stopped at $time because Tripping was stopped from Active '
            'apps or Settings, $lost',
        true,
        null,
      ),
      ExitCause.swiped => (
        'Recording stopped at $time because Tripping was swiped away from '
            'recent apps, $lost',
        true,
        null,
      ),
      ExitCause.crash => (
        'Recording stopped at $time because Tripping crashed, $lost',
        true,
        null,
      ),
      ExitCause.permission => (
        'Recording stopped at $time because location permission was turned '
            'off, $lost',
        true,
        null,
      ),
      ExitCause.update => (
        'Recording stopped at $time because Tripping was updated, $lost',
        true,
        null,
      ),
      ExitCause.memory => (
        'Recording stopped at $time: Android closed Tripping to free memory, '
            '$lost',
        true,
        battery,
      ),
      ExitCause.system || null => (
        'Recording stopped at $time. The phone closed Tripping, $lost If '
            'this keeps happening, set Tripping’s battery use to Unrestricted.',
        true,
        battery,
      ),
    };
  }
}

/// Android settings that silently undermine recording, stated up front.
class _SystemNotes extends StatelessWidget {
  const _SystemNotes({
    required this.state,
    required this.restricted,
    required this.notificationsShown,
    required this.onOpenAppSettings,
  });

  final RecorderState state;
  final bool restricted;
  final bool? notificationsShown;
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final notes = [
      if (restricted)
        'Battery use for Tripping is set to Restricted, so recording stops '
            'when you leave the app.',
      if (state is Recording && notificationsShown == false)
        'Recording continues, but Android isn’t showing its notification. '
            'Allow notifications for Tripping to see it.',
    ];
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                note,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: warningColor(context)),
              ),
            ),
          TextButton(
            onPressed: onOpenAppSettings,
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }
}

class _AccessProblem extends StatelessWidget {
  const _AccessProblem({
    required this.problem,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final LocationAccess problem;
  final VoidCallback? onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final (message, action, retries) = switch (problem) {
      LocationAccess.denied => (
        'Tripping needs your location to record a journey. It stays on this '
            'phone.',
        'Allow location',
        true,
      ),
      LocationAccess.deniedForever => (
        'Location is not allowed for Tripping. Allow it in Settings, then '
            'try again.',
        'Open settings',
        false,
      ),
      LocationAccess.approximate => (
        'Tripping only has approximate location, which is too coarse for a '
            'track. Turn on precise location in Settings.',
        'Open settings',
        false,
      ),
      LocationAccess.serviceOff => (
        'Location is turned off on this phone.',
        'Turn on location',
        false,
      ),
      LocationAccess.granted => ('', '', false),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: warningColor(context)),
          ),
          TextButton(
            onPressed: retries ? onRetry : onOpenSettings,
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
