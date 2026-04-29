import 'dart:async';

import '../journey/journey.dart';
import '../journey/journey_store.dart';
import 'fix_filter.dart';
import 'location_source.dart';
import 'track_policy.dart';
import 'track_stats.dart';

/// The active journey's numbers at one moment.
class Progress {
  const Progress({
    required this.meters,
    required this.movingTime,
    required this.closedTime,
    this.openSince,
    this.lastFix,
    this.climb,
    this.descent,
  });

  final double meters;
  final Duration movingTime;

  /// Metres up and down, or null while no fix has had a usable altitude.
  final double? climb;
  final double? descent;

  /// Recording time of the segments that have closed.
  final Duration closedTime;

  /// When the open segment began, while recording.
  final DateTime? openSince;

  /// The newest fix stored for the journey.
  final Fix? lastFix;

  /// Time spent recording up to [now], leaving out pauses and interruptions.
  Duration elapsedAt(DateTime now) {
    final since = openSince;
    if (since == null || now.isBefore(since)) return closedTime;
    return closedTime + now.difference(since);
  }
}

/// What the recorder is doing. The UI renders this and nothing else.
sealed class RecorderState {
  const RecorderState();
}

/// No journey is active.
final class Idle extends RecorderState {
  const Idle();
}

/// A journey is recording: its segment is open.
final class Recording extends RecorderState {
  const Recording({
    required this.journey,
    required this.progress,
    this.latestFix,
    this.latestFixArrivedAt,
    this.locationProblem,
    this.saveError,
  });

  final JourneyRow journey;
  final Progress progress;

  /// The device's newest usable fix in this segment, kept in the track or
  /// not (it may be too inaccurate). Null while waiting for the first one.
  final Fix? latestFix;

  /// When [latestFix] arrived, by the recorder's clock. Measure how long ago
  /// the last fix was against this, never against the fix's own GPS time.
  final DateTime? latestFixArrivedAt;

  /// Why fixes stopped arriving, usually a [LocationUnavailable]. The
  /// journey keeps recording; the gap shows in the track.
  final Object? locationProblem;

  /// Set while fixes cannot be saved. Nothing is counted until saving works
  /// again.
  final Object? saveError;
}

/// The user paused the journey.
final class Paused extends RecorderState {
  const Paused({required this.journey, required this.progress});

  final JourneyRow journey;
  final Progress progress;
}

/// Recording stopped without the user asking, for example because the
/// system closed the app. Nothing is known after [stoppedAt].
final class Interrupted extends RecorderState {
  const Interrupted({
    required this.journey,
    required this.progress,
    required this.stoppedAt,
  });

  final JourneyRow journey;
  final Progress progress;
  final DateTime stoppedAt;
}

/// Owns recording for a journey store: the location subscription, which
/// fixes are kept, and the live numbers.
///
/// Commands and fixes are handled strictly one at a time, in arrival order.
/// Commands are idempotent. Fixes are counted only after they are saved.
/// There is at most one recorder per store in a process, which is what makes
/// recovering an interrupted journey on [open] safe.
class Recorder {
  Recorder._(this._store, this._location, this._clock);

  static final _storesInUse = <JourneyStore>{};

  /// Opens the recorder for [store]. A journey left recording by a process
  /// that died is closed at its last saved fix and reported as
  /// [Interrupted].
  ///
  /// [clock] supplies wall-clock time for lifecycle events; fixes carry
  /// their own time, and the two are never compared.
  static Future<Recorder> open(
    JourneyStore store,
    LocationSource location, {
    DateTime Function()? clock,
  }) async {
    if (!_storesInUse.add(store)) {
      throw StateError('A recorder is already open for this store');
    }
    final recorder = Recorder._(store, location, clock ?? _utcNow);
    try {
      await store.recoverInterrupted();
      await recorder._restore();
    } catch (_) {
      _storesInUse.remove(store);
      rethrow;
    }
    return recorder;
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  final JourneyStore _store;
  final LocationSource _location;
  final DateTime Function() _clock;
  final _changes = StreamController<RecorderState>.broadcast();
  Future<void> _queue = Future.value();
  RecorderState _state = const Idle();
  StreamSubscription<Fix>? _subscription;
  int _segmentGeneration = 0;
  FixFilter? _filter;
  TrackStats? _stats;
  Duration _closedTime = Duration.zero;
  DateTime? _openSince;
  DateTime? _lastEventAt;
  Fix? _lastFix;

  RecorderState get state => _state;

  /// Every state change, as it happens.
  Stream<RecorderState> get changes => _changes.stream;

  /// Completes once every command and fix received so far is handled.
  Future<void> settled() => _serially(() async {});

  /// Starts a new journey, asking for location access first.
  ///
  /// Returns why it could not start, or [LocationAccess.granted]. Without
  /// access no journey is created. A no-op while a journey is active.
  Future<LocationAccess> start(JourneyMode mode) => _serially(() async {
    if (_state is! Idle) return LocationAccess.granted;
    final access = await _location.requestAccess();
    if (access != LocationAccess.granted) return access;

    final journey = await _store.startJourney(mode, at: _eventTime());
    final policy = TrackPolicy.of(mode);
    _filter = FixFilter(policy);
    _stats = TrackStats(policy);
    _closedTime = Duration.zero;
    _lastFix = null;
    _openSegment(journey, journey.createdAt);
    return access;
  });

  /// Closes the open segment. A no-op unless recording.
  Future<void> pause() => _serially(() async {
    final state = _state;
    if (state is! Recording) return;
    final at = _eventTime();
    await _store.pause(state.journey.id, at: at);
    await _closeSegment(at);
    _set(
      Paused(
        journey: state.journey.copyWith(status: JourneyStatus.paused),
        progress: _progress(),
      ),
    );
  });

  /// Opens a new segment of a paused or interrupted journey, asking for
  /// location access first. Returns why it could not, or
  /// [LocationAccess.granted]. A no-op unless paused or interrupted.
  Future<LocationAccess> resume() => _serially(() async {
    final journey = switch (_state) {
      Paused(:final journey) || Interrupted(:final journey) => journey,
      _ => null,
    };
    if (journey == null) return LocationAccess.granted;
    final access = await _location.requestAccess();
    if (access != LocationAccess.granted) return access;

    final at = _eventTime();
    await _store.resume(journey.id, at: at);
    _openSegment(journey.copyWith(status: JourneyStatus.recording), at);
    return access;
  });

  /// Ends the active journey and returns its final numbers, or null if
  /// nothing was active.
  Future<Progress?> end() => _serially(() async {
    final journey = switch (_state) {
      Recording(:final journey) ||
      Paused(:final journey) ||
      Interrupted(:final journey) => journey,
      Idle() => null,
    };
    if (journey == null) return null;
    final at = _eventTime();
    await _store.end(journey.id, at: at);
    await _closeSegment(at);
    final last = _progress();
    _filter = null;
    _stats = null;
    _set(const Idle());
    return last;
  });

  /// Stops listening and frees the store for another recorder. The journey
  /// is left exactly as it is in storage, as a process death would leave
  /// it.
  Future<void> close() async {
    await _serially(() async {
      ++_segmentGeneration;
      await _subscription?.cancel();
      _subscription = null;
    });
    _storesInUse.remove(_store);
    await _changes.close();
  }

  Future<void> _restore() async {
    final journey = await _store.activeJourney();
    if (journey == null) return;
    final policy = TrackPolicy.of(journey.mode);
    final segments = await _store.segmentsOf(journey.id);
    final track = await _store.track(journey.id);
    _lastFix = [for (final segment in track) ...segment].lastOrNull;
    _filter = FixFilter(policy, after: _lastFix?.time);
    _stats = TrackStats.replay(policy, track);
    for (final segment in segments) {
      final ended = segment.endedAt;
      if (ended != null && ended.isAfter(segment.startedAt)) {
        _closedTime += ended.difference(segment.startedAt);
      }
      _noteEvent(segment.startedAt);
      if (ended != null) _noteEvent(ended);
    }

    // A recovered journey is always paused: recoverInterrupted closed it.
    final last = segments.last;
    _set(
      last.endReason == SegmentEnd.interrupted
          ? Interrupted(
              journey: journey,
              progress: _progress(),
              stoppedAt: last.endedAt!,
            )
          : Paused(journey: journey, progress: _progress()),
    );
  }

  void _openSegment(JourneyRow journey, DateTime startedAt) {
    final generation = ++_segmentGeneration;
    _filter!.startSegment();
    _stats!.startSegment();
    _openSince = startedAt;
    _subscription = _location
        .watch(journey.mode)
        .listen(
          (fix) => _serially(() async {
            if (generation == _segmentGeneration) {
              await _record(journey.id, fix);
            }
          }),
          onError: (Object problem) => _serially(() async {
            if (generation == _segmentGeneration) {
              _locationLost(journey.id, problem);
            }
          }),
        );
    _set(Recording(journey: journey, progress: _progress()));
  }

  Future<void> _closeSegment(DateTime at) async {
    ++_segmentGeneration;
    await _subscription?.cancel();
    _subscription = null;
    final since = _openSince;
    if (since != null) _closedTime += at.difference(since);
    _openSince = null;
  }

  Future<void> _record(int journeyId, Fix fix) async {
    final state = _state;
    if (state is! Recording || state.journey.id != journeyId) return;
    final verdict = _filter!.judge(fix);
    final arrivedAt = _clock();
    if (verdict == FixVerdict.inaccurate) {
      _set(
        Recording(
          journey: state.journey,
          progress: state.progress,
          latestFix: fix,
          latestFixArrivedAt: arrivedAt,
          saveError: state.saveError,
        ),
      );
    }
    if (!verdict.belongsInTrack) return;

    Object? saveError;
    try {
      switch (await _store.append(journeyId, fix)) {
        case AppendResult.stored:
          _stats!.add(fix);
          _lastFix = fix;
        case AppendResult.duplicate:
          break;
        case AppendResult.notRecording:
          saveError = StateError('Storage no longer has this journey open');
      }
    } catch (error) {
      saveError = error;
    }
    _set(
      Recording(
        journey: state.journey,
        progress: _progress(),
        latestFix: fix,
        latestFixArrivedAt: arrivedAt,
        saveError: saveError,
      ),
    );
  }

  void _locationLost(int journeyId, Object problem) {
    final state = _state;
    if (state is! Recording || state.journey.id != journeyId) return;
    _set(
      Recording(
        journey: state.journey,
        progress: state.progress,
        latestFix: state.latestFix,
        latestFixArrivedAt: state.latestFixArrivedAt,
        locationProblem: problem,
        saveError: state.saveError,
      ),
    );
  }

  Progress _progress() => Progress(
    meters: _stats?.meters ?? 0,
    movingTime: _stats?.movingTime ?? Duration.zero,
    closedTime: _closedTime,
    openSince: _openSince,
    lastFix: _lastFix,
    climb: _stats?.elevation.climb,
    descent: _stats?.elevation.descent,
  );

  /// Wall-clock time for a lifecycle event, never earlier than the previous
  /// one: a clock set back must not end a segment before it began.
  DateTime _eventTime() {
    final now = _clock();
    final last = _lastEventAt;
    final at = last != null && now.isBefore(last) ? last : now;
    _noteEvent(at);
    return at;
  }

  void _noteEvent(DateTime at) {
    final last = _lastEventAt;
    if (last == null || at.isAfter(last)) _lastEventAt = at;
  }

  void _set(RecorderState state) {
    _state = state;
    if (!_changes.isClosed) _changes.add(state);
  }

  Future<T> _serially<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
