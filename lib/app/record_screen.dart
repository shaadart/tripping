import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../recording/location_source.dart';
import '../recording/recorder.dart';
import '../recording/track_policy.dart';
import 'figure.dart';
import 'format.dart';
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
    this.onToggleHighSun,
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

  /// Switches the high-contrast look for bright daylight on or off.
  final VoidCallback? onToggleHighSun;
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

  /// The destination of the journey shown, and the way there.
  StreamSubscription<RouteRow?>? _routeWatch;
  int? _routeJourney;
  RouteRow? _route;
  RouteError? _routeWhy;
  bool _planning = false;

  /// Progress along the way, from the newest live fix.
  RouteFollower? _follower;
  RouteProgress? _progress;
  DateTime? _followedFix;
  DateTime? _replannedAt;

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
    _changes = widget.recorder.changes.listen((state) {
      setState(() => _state = state);
      _syncTicker();
      _followRoute(state);
      _follow();
    });
    _syncTicker();
    _followRoute(_state);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshSystem());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_changes.cancel());
    unawaited(_routeWatch?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshSystem());
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
    if (_state is Recording) {
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

  /// A new way from here, keeping the old one if none comes. [asked] by
  /// the user goes ahead at once.
  void _replan({bool asked = false}) {
    final at = widget.clock();
    final last = _replannedAt;
    if (!asked && last != null && at.difference(last) < _replanEvery) return;
    _replannedAt = at;
    _planIfDue(again: true, keepOnFailure: true);
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
                            route: _route,
                            why: _routeWhy,
                            planning: _planning,
                            progress: _progress,
                            now: now,
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
    required this.route,
    required this.why,
    required this.planning,
    required this.progress,
    required this.now,
    required this.onSearch,
    required this.onClear,
    required this.onRetry,
  });

  final RouteRow? route;
  final RouteError? why;
  final bool planning;

  /// How far along the way, while recording with a live fix.
  final RouteProgress? progress;
  final DateTime now;
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
        '${kilometres(meters)} by road'
            '${seconds == null ? '' : ' · ${_roughly(seconds)}'}',
        false,
      ),
      (RouteKind.road, _) => (
        '${kilometres(meters)} to go by road'
            '${seconds == null ? '' : ' · ${_roughly(seconds)}, arriving '
                      'around ${_clock(context, seconds)}'}',
        false,
      ),
      (RouteKind.straight, _) => (
        '${kilometres(meters)} in a straight line, not by road. '
            '${planning ? 'Looking for a road…' : why?.message ?? 'No road route was found.'}',
        !planning,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _DestinationCard(
        title: 'To ${route.destination}',
        subtitle: subtitle,
        onSearch: onSearch,
        onClear: onClear,
        action: retry ? (label: 'Try again', onPressed: onRetry) : null,
      ),
    );
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
        'Paused. Nothing is recorded until you resume.',
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
