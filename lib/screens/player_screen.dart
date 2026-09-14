// Professional IPTV Player Screen with custom controls overlay.
// Replaces Chewie controls with a fully custom UI matching modern IPTV players.
// Features: auto-hide controls, double-tap seek, settings sheet, lock screen,
// quality display, seek bar, and right-side action buttons.

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:window_manager/window_manager.dart';
import '../core/build_flavor.dart' show kIsDesktop, kIsTv, kIsTvRemote;
import '../providers/user_prefs_provider.dart';
import '../services/player_backend.dart';
import '../services/player_backend_factory.dart';
import '../services/stream_url_fallback.dart';
import '../theme/app_type.dart';

/// The TV transport row's buttons, left to right — VOD/series only (see
/// _tvControlActions; live never builds this list at all, its own
/// left/right-to-change-channel behavior in _handlePlayerKeyEvent is
/// untouched by any of this).
enum _TvControlAction { previous, rewind, playPause, forward, next }

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String? coverUrl;
  final bool isLive;
  final String? mediaId;
  final MediaType? mediaType;
  final Map<String, dynamic>? rawMediaData;
  final int initialPositionSeconds;
  final List<Map<String, dynamic>>? playlist;
  final int initialIndex;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.coverUrl,
    this.isLive = false,
    this.mediaId,
    this.mediaType,
    this.rawMediaData,
    this.initialPositionSeconds = 0,
    this.playlist,
    this.initialIndex = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

/// The player's accent — scrubber, progress and TV focus.
///
/// A constant rather than a theme lookup: the player is always true black in
/// every theme, so a token that flips with brightness would be wrong here.
const Color _playerAccent = Color(0xFF9B3BAF);

/// Pauses before each automatic re-open of a stream that failed to start —
/// twelve seconds in all before the error screen is shown. See
/// _handlePlaybackFailure for why a failure to start is retried at all.
const List<Duration> _openRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 6),
];

/// The pause before a retry that switches to the fallback address. Short,
/// because nothing is waited out: the first address failed because of what it
/// was, not because of when it was asked for.
const Duration _fallbackSwitchDelay = Duration(milliseconds: 400);

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ─── Video Controller ──────────────────────────────────────────────────────
  PlayerBackend? _backend;
  bool _isInitializing = true;
  bool _isBuffering = false;
  String? _errorMessage;

  /// Automatic re-opens used so far for the current item. Reset when playback
  /// actually begins, for a new item, and on a manual Retry.
  int _openAttempt = 0;

  /// The pending automatic re-open, kept so leaving the screen can cancel it.
  Timer? _openRetryTimer;

  /// True for the whole of _initPlayer: the open and, when resuming, the
  /// play-then-seek that follows it. A failure anywhere in that window is a
  /// failure to start, even though play() has already been called.
  bool _openInProgress = false;

  /// Moves on whenever an open starts or is abandoned. An _initPlayer run that
  /// finds it changed after one of its awaits has been superseded — by a
  /// retry, an episode switch or leaving the screen — and stops without
  /// touching the player or the screen's state.
  int _openGeneration = 0;
  Timer? _historyTimer;

  // ─── Stream Subscriptions ─────────────────────────────────────────────────
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<int?>? _widthSubscription;
  StreamSubscription<int?>? _heightSubscription;

  // ─── Cached Player State ──────────────────────────────────────────────────
  bool _isPlaying = false;
  // Distinct from _isPlaying: many backends report `playing: false` on the
  // raw stream for a moment while buffering/seeking, not just when the user
  // actually paused — most visible on TV when seeking fast (several D-pad
  // right presses in quick succession each kick off a seek that briefly
  // stalls playback). _handlePlayerKeyEvent used to key its "paused, so
  // left/right navigate the transport row instead of seeking" branch off
  // !_isPlaying directly, so that momentary buffering blip was
  // indistinguishable from a real pause: mid fast-seek, the row would
  // suddenly "steal" left/right into button navigation instead of
  // continuing to seek. This only ever flips inside _togglePlayPause, i.e.
  // only on an explicit user action, so a buffering-induced dip in
  // _isPlaying never touches it.
  bool _isUserPaused = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int? _videoWidth;
  int? _videoHeight;
  Duration? _lastRawPosition;
  bool _inSeekGracePeriod = false;
  Timer? _seekGraceTimer;

  // ─── Controls State ────────────────────────────────────────────────────────
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideTimer;
  bool _isDraggingSeek = false;
  double _dragSeekValue = 0.0;
  int _lastSaveTime = 0;

  // ─── TV transport row (VOD/series only — see _tvControlActions) ───────────
  // Null until the user actually moves into the row with left/right, so it
  // defaults to Play/Pause the first time (see _tvHighlightedControl)
  // without needing every pause to explicitly reset it.
  _TvControlAction? _tvFocusedControl;

  // ─── Settings State ────────────────────────────────────────────────────────

  // ─── Manual Rotate State ───────────────────────────────────────────────────
  // -1 = not yet forced (following the initial landscape-both default).
  // Cycles Vertical → Horizontal Right → Horizontal Left → Vertical → ...
  int _rotationIndex = -1;
  static const List<DeviceOrientation> _rotationOrientations = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.landscapeLeft,
  ];
  static const List<String> _rotationLabels = [
    'Vertical',
    'Horizontal Right',
    'Horizontal Left',
  ];
  static const List<String> _rotationLabelsAr = [
    'عمودي',
    'أفقي يمين',
    'أفقي يسار',
  ];

  String _rotationLabel(int index, bool isArabic) {
    return isArabic ? _rotationLabelsAr[index] : _rotationLabels[index];
  }

  // ─── Swipe Controls (Brightness/Volume) ────────────────────────────────────
  double? _dragStartY;
  double? _startVolume;
  double? _startBrightness;
  String _indicatorMessage = '';
  Timer? _indicatorTimer;

  // ─── Explicit Brightness/Volume State ──────────────────────────────────────
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;
  StreamSubscription<double>? _brightnessSubscription;

  // ─── Playlist State ────────────────────────────────────────────────────────
  late int _currentIndex;
  late String _currentStreamUrl;
  late String _currentTitle;
  late String? _currentCoverUrl;
  late bool _currentIsLive;
  late String? _currentMediaId;
  late MediaType? _currentMediaType;
  late Map<String, dynamic>? _currentRawMediaData;

  // ─── Double Tap Seek Animation ─────────────────────────────────────────────
  bool _showLeftSeek = false;
  bool _showRightSeek = false;
  Timer? _leftSeekTimer;
  Timer? _rightSeekTimer;

  // ─── First-Run Gesture Tutorial ─────────────────────────────────────────────
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[PlayerScreen] url: ${widget.streamUrl}');
    // Initialize playlist state
    _currentIndex = widget.initialIndex;
    _currentStreamUrl = widget.streamUrl;
    _currentTitle = widget.title;
    _currentCoverUrl = widget.coverUrl;
    _currentIsLive = widget.isLive;
    _currentMediaId = widget.mediaId;
    _currentMediaType = widget.mediaType;
    _currentRawMediaData = widget.rawMediaData;

    // Force landscape for immersive video playback
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Immersive fullscreen — hide system bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable(); // Keep screen awake
    _initPlayer();
    // Brightness/volume sliders and the swipe gesture that drives them need
    // a touchscreen — gated on kIsTvRemote (not kIsTv), since iPad running
    // the TV UI still has one and should keep these, unlike an actual TV
    // remote (see build_flavor.dart's doc comment on kIsTvRemote).
    if (!kIsTvRemote) _initVolumeAndBrightness();

    // Shown at most once ever, device-wide — see markPlayerTutorialSeen().
    // Skipped only for an actual remote: it explains swipe gestures for
    // brightness/volume, which don't exist without a touchscreen (see
    // _buildVideoLayer/_buildControlsOverlay).
    if (!kIsTvRemote) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final userPrefs = context.read<UserPrefsProvider>();
        if (!userPrefs.hasSeenPlayerTutorial) {
          setState(() => _showTutorial = true);
        }
      });
    }
  }

  void _dismissTutorial() {
    setState(() => _showTutorial = false);
    context.read<UserPrefsProvider>().markPlayerTutorialSeen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _saveCurrentPosition();
    }
  }

  Future<void> _initVolumeAndBrightness() async {
    try {
      _currentVolume = await VolumeController.instance.getVolume();
    } catch (_) {}
    try {
      _currentBrightness = await ScreenBrightness().current;
    } catch (_) {}
    if (mounted) setState(() {});

    VolumeController.instance.addListener((volume) {
      if (mounted) setState(() => _currentVolume = volume);
    });
    _brightnessSubscription = ScreenBrightness().onCurrentBrightnessChanged
        .listen((brightness) {
          if (mounted) setState(() => _currentBrightness = brightness);
        });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Player Initialization
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _initPlayer() async {
    final generation = ++_openGeneration;
    bool superseded() => generation != _openGeneration || !mounted;
    _openInProgress = true;
    // Clear the previous item's cached playback state before opening the new
    // one. These only ever get written from backend stream events, so without
    // an explicit reset they still hold the *previous* episode's values here —
    // which makes the readiness wait below (`_duration == 0 && _position == 0`)
    // fall straight through on every switch instead of giving the freshly
    // opened engine time to settle. VLCKit then receives play() while it is
    // still tearing down/reloading media and ends up parked in a stopped
    // state: play button showing, no timeline, no video.
    _seekGraceTimer?.cancel();
    _inSeekGracePeriod = false;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
      _isBuffering = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isPlaying = false;
      _isUserPaused = false;
      _videoWidth = null;
      _videoHeight = null;
      _lastRawPosition = null;
    });

    try {
      // A local reference: _backend can be replaced or nulled while this
      // run is awaiting, and a superseded run must not act on either.
      final backend = createPlayerBackend();
      _backend = backend;

      // Subscribe to backend streams for reactive state updates
      _subscribeToBackendStreams();

      // Open the media strictly without playing to prevent overriding position
      await backend.open(
        url: _currentStreamUrl,
        httpHeaders: const {'User-Agent': kIptvUserAgent},
        autoPlay: false,
      );

      // Give the engine a bounded window to report signs of life (duration
      // for VOD, or position starting to advance for live/seekless streams)
      // before touching play/seek or revealing the player. Some engines
      // (VLC) finish native init asynchronously after open() already
      // returned, so without this the player could briefly show a blank
      // black frame instead of the loading spinner while it catches up.
      int readyWaits = 0;
      while (_duration.inMilliseconds == 0 &&
          _position.inMilliseconds == 0 &&
          readyWaits < 100 &&
          !superseded()) {
        await Future.delayed(const Duration(milliseconds: 50));
        readyWaits++;
      }

      if (superseded()) return;
      // Restore exact position for non-live content
      if (!_currentIsLive) {
        int targetPos = 0;
        if (_currentMediaId != null && mounted) {
          targetPos = context
              .read<UserPrefsProvider>()
              .getHistoryPositionMilliseconds(_currentMediaId!);
          debugPrint('[Player History] Episode ID Loaded: $_currentMediaId');
          debugPrint('[Player History] Episode ID Saved: $_currentMediaId');
        }

        if (targetPos == 0 && _currentIndex == widget.initialIndex) {
          targetPos = widget.initialPositionSeconds * 1000;
        }

        if (targetPos > 0) {
          debugPrint('[Player History] Saved Position: $targetPos ms');
          debugPrint('[Player History] Loaded Position: $targetPos ms');

          // Wait for player to be fully initialized and report a duration
          int durationWaits = 0;
          while (_duration.inMilliseconds == 0 &&
              durationWaits < 100 &&
              !superseded()) {
            await Future.delayed(const Duration(milliseconds: 50));
            durationWaits++;
          }

          debugPrint(
            '[Player History] Player Initialized: ${_duration.inMilliseconds > 0}',
          );

          if (superseded()) return;
          // CRITICAL FIX FOR ANDROID: Start playing before seeking.
          // If play is false, libmpv/ExoPlayer on Android may ignore the seek command
          // or reset to the first keyframe because the codec is not fully initialized.
          await backend.play();

          // Wait until the player actually starts progressing (position > 0)
          // This guarantees that the native engine is fully prepared and actively playing,
          // so it won't reset our seek back to 0.
          int playWaits = 0;
          while (backend.position.inMilliseconds == 0 &&
              playWaits < 40 &&
              !superseded()) {
            await Future.delayed(const Duration(milliseconds: 50));
            playWaits++;
          }

          if (superseded()) return;
          // Issue the exact seek
          debugPrint('[Player History] Seek Requested: $targetPos ms');
          await backend.seek(Duration(milliseconds: targetPos));
          debugPrint('[Player History] Seek Completed: $targetPos ms');

          if (superseded()) return;
          // Strict polling loop to verify the engine actually jumped to the position
          int seekWaits = 0;
          while (seekWaits < 100 && !superseded()) {
            final currentPos = backend.position.inMilliseconds;
            // Allow a 1.5 second variance (keyframes can snap position slightly)
            if ((currentPos - targetPos).abs() <= 1500 ||
                currentPos >= targetPos) {
              break;
            }
            await Future.delayed(const Duration(milliseconds: 50));
            seekWaits++;
          }

          debugPrint(
            '[Player History] Current Position After Seek: ${backend.position.inMilliseconds} ms',
          );
        }
      }

      if (superseded()) return;
      // ONLY start playback after the seek verification completes (safe to call again)
      await backend.play();

      if (superseded()) return;
      _startHideTimer();

      _openInProgress = false;
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      debugPrint('[PlayerScreen] Playback init error: $e');
      // A run abandoned mid-way throws here too, when the engine it was using
      // is disposed under it. That is not a new failure, and starting another
      // retry from it is how two retry chains would end up running at once.
      if (superseded()) return;
      // Classified while _openInProgress is still true, so a throw during
      // the resume seek counts as a failure to start.
      _handlePlaybackFailure(e.toString().replaceFirst('Exception: ', ''));
      // The handler supersedes this run when it schedules a retry; the flag
      // then stays set, keeping saves blocked until the retry opens.
      if (!superseded()) _openInProgress = false;
    }
  }

  /// Subscribe to all backend state streams for reactive UI updates.
  void _subscribeToBackendStreams() {
    _playingSubscription = _backend!.playingStream.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
          // Playback started — the video is live, so definitely not
          // "initializing" any more. This is the primary fix for the
          // loading spinner getting stuck: _isInitializing is cleared
          // the instant the engine confirms it is playing, regardless
          // of whether _initPlayer's own setState ran yet.
          if (playing && _isInitializing) {
            _isInitializing = false;
          }
          // Playing proves the provider accepted the connection, so a later
          // failure on this item starts its retries from the beginning.
          if (playing) {
            _openAttempt = 0;
          }
          // Similarly, if the engine says "playing" but the buffering
          // flag was never cleared, force-clear it now.
          if (playing && _isBuffering) {
            _isBuffering = false;
          }
          // Remote: a paused video with no visible controls looks stuck —
          // a remote has no touch-tap to bring them back, so once paused
          // they stay up (no auto-hide) until playback resumes. Phone and
          // iPad keep the existing tap-to-toggle/auto-hide behavior, since
          // pausing there doesn't strand the user the same way — both have
          // a touchscreen to bring controls back with.
          if (kIsTvRemote && !_isLocked) {
            if (!playing) {
              _hideTimer?.cancel();
              _showControls = true;
            } else {
              _resetHideTimer();
              // Next pause starts back at Play/Pause rather than wherever
              // the highlight happened to be left last time.
              _tvFocusedControl = null;
            }
          }
        });
      }
    });

    _positionSubscription = _backend!.positionStream.listen((position) {
      if (mounted && !_isDraggingSeek) {
        setState(() {
          _position = position;
          // Position actually moving forward is unambiguous proof playback
          // is active. Some engines can report a stale "buffering" flag
          // that never flips back on its own, leaving the buffering
          // spinner stuck over an already-playing video indefinitely —
          // this is a defensive backstop for that, regardless of engine.
          if (_isBuffering &&
              !_inSeekGracePeriod &&
              _lastRawPosition != null &&
              position > _lastRawPosition!) {
            _isBuffering = false;
          }
          // Safety net: if position is advancing, the video is playing.
          // Clear the loading overlay if it's still showing.
          if (_isInitializing &&
              _lastRawPosition != null &&
              position > _lastRawPosition!) {
            _isInitializing = false;
          }
        });
        _lastRawPosition = position;
        // Continuously update position (throttle to avoid UI jank)
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastSaveTime > 3000) {
          _saveCurrentPosition();
          _lastSaveTime = now;
        }
      }
    });

    _durationSubscription = _backend!.durationStream.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });

    _bufferingSubscription = _backend!.bufferingStream.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _errorSubscription = _backend!.errorStream.listen((error) {
      if (error.isNotEmpty && mounted) {
        debugPrint('[PlayerScreen] Playback error: $error');
        _handlePlaybackFailure(error);
      }
    });

    _completedSubscription = _backend!.completedStream.listen((completed) {
      if (completed && mounted) {
        // Auto-play next in playlist only for TV series if enabled
        if (_currentMediaType == MediaType.series) {
          final autoPlayEnabled = context
              .read<UserPrefsProvider>()
              .autoPlayNextEpisode;
          if (autoPlayEnabled &&
              widget.playlist != null &&
              _currentIndex < widget.playlist!.length - 1) {
            _playNext();
          }
        }
      }
    });

    _widthSubscription = _backend!.widthStream.listen((width) {
      if (mounted) setState(() => _videoWidth = width);
    });

    _heightSubscription = _backend!.heightStream.listen((height) {
      if (mounted) setState(() => _videoHeight = height);
    });
  }

  /// Cancel all player stream subscriptions.
  void _cancelSubscriptions() {
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // History Tracking (Save Logic)
  // ═══════════════════════════════════════════════════════════════════════════

  void _saveCurrentPosition() {
    if (_backend == null || !mounted) return;
    // Nothing correct can be saved while a stream is still opening or waiting
    // to be retried. Resuming calls play() before it seeks, so the position
    // at that moment is a fraction of a second into the file — and saving it
    // would overwrite the real resume point, sending every retry, and the
    // next visit, back to the start of the episode. The stored position
    // already is the resume point throughout that window.
    if (_openInProgress || (_openRetryTimer?.isActive ?? false)) return;
    if (_currentIsLive ||
        _currentMediaId == null ||
        _currentMediaType == null ||
        _currentRawMediaData == null) {
      return;
    }

    final rawPosition = _position.inMilliseconds;
    final duration = _duration.inMilliseconds;

    // Treat "basically at the end" as finished rather than saving a resume
    // point there — without this, a saved position within the last few
    // seconds of a *short* video (a demo clip, a short-form episode) gets
    // silently re-applied via initialPositionSeconds on the next open with
    // no resume dialog (that only shows above 30s saved), which looks like
    // the player skipping straight to near the end instead of playing from
    // the start. Matches the standard "mark as watched" behavior most
    // players use instead of ever resuming inside the last few seconds.
    // Explicitly saved as 0 (not just skipped) so this also clears out any
    // stale resume point already saved from an earlier, shorter session.
    final isEffectivelyFinished =
        duration > 0 &&
        (duration - rawPosition <= 15000 || rawPosition >= duration * 0.95);
    final position = isEffectivelyFinished ? 0 : rawPosition;

    if (position > 0 || isEffectivelyFinished) {
      context.read<UserPrefsProvider>().saveHistory(
        id: _currentMediaId!,
        title: _currentTitle,
        posterUrl: _currentCoverUrl ?? '',
        type: _currentMediaType!,
        positionMilliseconds: position,
        durationMilliseconds: duration,
        rawData: _currentRawMediaData!,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Playlist Controls
  // ═══════════════════════════════════════════════════════════════════════════

  void _playIndex(int index) async {
    if (widget.playlist == null ||
        index < 0 ||
        index >= widget.playlist!.length) {
      return;
    }

    // Save the current position before switching — and before the retry
    // state below is cleared, so the save guard still recognises an open that
    // never got going and does not write its pre-seek position over the
    // resume point.
    _saveCurrentPosition();

    // A different item gets its own full set of retries, and any open still
    // running for the old one is abandoned.
    _supersedeOpen();
    _openRetryTimer?.cancel();
    _openAttempt = 0;

    _cancelSubscriptions();
    _historyTimer?.cancel();
    try {
      await _backend?.stop();
      await _backend?.dispose();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _backend = null;
      });
    }

    // Completely clear old media source before loading new one to prevent audio-only issue
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    final item = widget.playlist![index];

    debugPrint('[Player Navigation] Current Episode ID: $_currentMediaId');
    debugPrint('[Player Navigation] Target Episode ID: ${item['mediaId']}');
    debugPrint('[Player Navigation] Current stream URL: $_currentStreamUrl');
    debugPrint('[Player Navigation] New stream URL: ${item['url']}');

    setState(() {
      _currentIndex = index;
      _currentStreamUrl = item['url'];
      _currentTitle = item['title'];
      _currentCoverUrl = item['coverUrl'];
      _currentIsLive = item['isLive'] ?? false;
      _currentMediaId = item['mediaId'];
      _currentMediaType = item['mediaType'];
      _currentRawMediaData = item['rawMediaData'];
    });

    _initPlayer();
  }

  void _playNext() {
    final playlist = widget.playlist;
    if (playlist == null || playlist.length < 2) return;
    if (_currentIndex < playlist.length - 1) {
      _playIndex(_currentIndex + 1);
      return;
    }
    // Live wraps: channel surfing past the last channel returns to the
    // first, the way it does on a TV's own tuner. Deliberately not applied
    // to VOD/series, where running past the last episode means "finished",
    // not "start the season over".
    if (_currentIsLive) _playIndex(0);
  }

  void _playPrevious() {
    final playlist = widget.playlist;
    if (playlist == null || playlist.length < 2) return;
    if (_currentIndex > 0) {
      _playIndex(_currentIndex - 1);
      return;
    }
    if (_currentIsLive) _playIndex(playlist.length - 1);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TV transport row (VOD/series, paused only) ────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════

  /// Which buttons the row actually has right now — Previous/Next only when
  /// there's really a playlist to move through (matches the same
  /// `hasPlaylist` gate _buildCenterControls already used, so Movies, which
  /// never gets a `playlist` at all — see tv_movie_detail_screen.dart —
  /// never shows episode buttons that would do nothing).
  List<_TvControlAction> get _tvControlActions {
    final hasPlaylist = widget.playlist != null && widget.playlist!.length > 1;
    return [
      if (hasPlaylist) _TvControlAction.previous,
      _TvControlAction.rewind,
      _TvControlAction.playPause,
      _TvControlAction.forward,
      if (hasPlaylist) _TvControlAction.next,
    ];
  }

  /// Defaults to Play/Pause the first time the row appears (or after it's
  /// been reset — see _togglePlayPause) rather than requiring every caller
  /// to know that default themselves.
  _TvControlAction _tvHighlightedControl(List<_TvControlAction> actions) {
    final current = _tvFocusedControl;
    if (current != null && actions.contains(current)) return current;
    return _TvControlAction.playPause;
  }

  void _tvMoveControlFocus(int delta) {
    final actions = _tvControlActions;
    final currentIndex = actions.indexOf(_tvHighlightedControl(actions));
    final nextIndex = (currentIndex + delta).clamp(0, actions.length - 1);
    setState(() => _tvFocusedControl = actions[nextIndex]);
    _resetHideTimer();
  }

  void _tvActivateHighlightedControl() {
    switch (_tvHighlightedControl(_tvControlActions)) {
      case _TvControlAction.previous:
        _playPrevious();
      case _TvControlAction.rewind:
        _seekRelative(-10);
      case _TvControlAction.playPause:
        _togglePlayPause();
      case _TvControlAction.forward:
        _seekRelative(10);
      case _TvControlAction.next:
        _playNext();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Controls Visibility
  // ═══════════════════════════════════════════════════════════════════════════

  void _toggleControls() {
    if (_isLocked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls && !_isDraggingSeek) {
        setState(() => _showControls = false);
      }
    });
  }

  void _resetHideTimer() {
    if (_showControls) _startHideTimer();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Playback Controls
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handles TV remote / physical keyboard input. This screen is otherwise
  /// entirely gesture-driven (swipe for brightness/volume, double-tap to
  /// seek) — those gestures have no D-pad equivalent, so instead of trying
  /// to focus-navigate onto tiny on-screen controls, common remote keys map
  /// directly to the same actions regardless of what's focused: Select/
  /// Enter/media-play-pause toggles playback, D-pad left/right seeks the
  /// same 10s step the double-tap gesture already uses, D-pad down reveals
  /// the controls overlay. Mirrors the existing lock behavior — a locked
  /// screen ignores these the same way it already ignores touch gestures.
  KeyEventResult _handlePlayerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isLocked) return KeyEventResult.ignored;

    final key = event.logicalKey;

    // Actual remote, VOD/series, paused: the transport row is "live" for
    // the D-pad — left/right move a highlight along it instead of seeking,
    // and select activates whichever button is currently highlighted
    // rather than always just toggling play/pause. Playing (or live, or
    // phone/iPad) falls through to the unconditional behavior below exactly
    // as before. kIsTvRemote, not kIsTv: iPad no longer renders that
    // transport row at all (see _buildTvTransportRow's call site) since it
    // has the full on-screen button row instead, so this branch would
    // otherwise silently swallow left/right into navigating a highlight
    // nothing on screen shows — e.g. from a Bluetooth keyboard/controller.
    if (kIsTvRemote && !_currentIsLive && _isUserPaused) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _tvMoveControlFocus(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _tvMoveControlFocus(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.gameButtonA) {
        _tvActivateHighlightedControl();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.gameButtonA) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    // On live there is nothing to seek through, so left/right change
    // channel instead — matching what those keys do on a normal TV remote,
    // and replacing the prev/next buttons that _buildCenterControls no
    // longer draws for live.
    if (_currentIsLive) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.mediaRewind ||
          key == LogicalKeyboardKey.mediaTrackPrevious) {
        _playPrevious();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.mediaFastForward ||
          key == LogicalKeyboardKey.mediaTrackNext) {
        _playNext();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.mediaTrackPrevious ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      // VOD/series: a remote's dedicated skip-track buttons (distinct from
      // arrow left/right, which seek instead) jump episodes regardless of
      // play/pause state — the one way to change episode without pausing
      // first, mirroring how a real TV remote's skip buttons work on any
      // playlist-based source. _playNext/_playPrevious already no-op on a
      // single-item or absent playlist (Movies), so this is safe to wire
      // unconditionally rather than re-checking hasPlaylist here too.
      if (key == LogicalKeyboardKey.mediaTrackPrevious) {
        _playPrevious();
      } else {
        _playNext();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      // Reuses the double-tap-to-rewind path (not a bare _seekRelative)
      // specifically for its -10s flash overlay — a remote seek needs the
      // same "yes, that registered" confirmation a touch double-tap
      // already gets, especially since this can fire while the main
      // controls are hidden.
      _onDoubleTapLeft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      _onDoubleTapRight();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && !_showControls) {
      _toggleControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _togglePlayPause() {
    if (_backend == null) return;
    final wasPlaying = _isPlaying;
    _backend!.playOrPause();
    setState(() => _isUserPaused = wasPlaying);
    _resetHideTimer();
    if (_isPlaying) {
      _saveCurrentPosition();
    }
  }

  void _seekRelative(int seconds) {
    if (_backend == null) return;
    final current = _position;
    final duration = _duration;
    final target = current + Duration(seconds: seconds);
    final clampedTarget = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);
    _backend!.seek(clampedTarget);
    _watchSeek(clampedTarget);
    _resetHideTimer();
  }

  /// A manual seek (seek bar drag, double-tap ±10s) doesn't otherwise get
  /// any timeout/feedback if the engine hangs on it — unlike the history
  /// resume-seek in [_initPlayer], which already polls with a bound. This
  /// gives the same kind of bounded visibility here: if playback hasn't
  /// caught up to roughly where we asked it to go within a few seconds,
  /// say so instead of leaving the screen looking frozen with no clue why.
  void _watchSeek(Duration target) {
    // Suppress the "position is advancing so force-clear buffering" logic
    // for a few seconds after a seek — a big forward seek can legitimately
    // land on a position "greater than before" while still genuinely
    // buffering, which would otherwise look identical to the stuck-spinner
    // bug this is meant to fix.
    _inSeekGracePeriod = true;
    _seekGraceTimer?.cancel();
    _seekGraceTimer = Timer(const Duration(seconds: 3), () {
      _inSeekGracePeriod = false;
    });
  }

  /// Abandons any open still running, so it stops at its next await.
  void _supersedeOpen() => _openGeneration++;

  /// Decides what a playback failure means before showing it.
  ///
  /// A movie or episode that fails to *start* is usually still playable, for
  /// one of two reasons.
  ///
  /// The address is being answered from a stale cache. Xtream panels commonly
  /// sit behind Cloudflare, which caches `.mp4` addresses; a brief panel
  /// failure on one becomes a 404 served to every request for that address
  /// for several minutes. This is what made resuming some episodes fail: the
  /// provider catalogues them as `.mp4`, the cached 404 answered every
  /// attempt, and waiting a few minutes cleared it. Retrying the same address
  /// cannot help — the cache answers again — so the first retry switches to
  /// the same file under `.ts`, which is not cached that way. See
  /// xtreamFallbackStreamUrl. Diagnosed against a live panel, where `.mp4`
  /// returned a cached 404 while `.ts`, `.mkv` and `.avi` all redirected to the
  /// real stream.
  ///
  /// Or the panel is refusing a second connection. Accounts are often limited
  /// to one, and a panel can keep counting the previous one for a little while
  /// after the app has closed it. Waiting is the only remedy there, so the
  /// remaining retries back off (_openRetryDelays).
  ///
  /// So a failure before playback begins is retried quietly behind the loading
  /// spinner, and only when the retries run out does the error screen appear.
  /// A failure after playback has started is a dropped connection mid-stream,
  /// and is shown as before.
  void _handlePlaybackFailure(String message) {
    if (!mounted) {
      return;
    }
    // Engines can report one failure several times; one pending retry covers
    // all of them.
    if (_openRetryTimer?.isActive ?? false) {
      return;
    }

    // Resuming from history calls play() and then seeks, and that seek opens
    // a second request to the provider — which can be the one refused. By
    // then _isPlaying may already be true, so "is it playing" alone would
    // misfile exactly the failure this exists for as a mid-stream drop.
    final startedPlaying =
        !_openInProgress && (_isPlaying || _position > Duration.zero);
    if (!startedPlaying && _openAttempt < _openRetryDelays.length) {
      // Switch to the fallback address once, on the first retry; its own
      // fallback is null, so later retries keep using it.
      final fallback = xtreamFallbackStreamUrl(_currentStreamUrl);
      final delay = fallback != null
          ? _fallbackSwitchDelay
          : _openRetryDelays[_openAttempt];
      _openAttempt++;
      debugPrint(
        '[PlayerScreen] Open failed ($message); '
        'retry $_openAttempt of ${_openRetryDelays.length} in ${delay.inSeconds}s',
      );
      // Stop the failed run where it stands, and silence its engine: while
      // the retry waits, a failed engine can still report a position (which
      // would be saved over the resume point) or a play state (which would
      // hide the spinner).
      _supersedeOpen();
      _cancelSubscriptions();
      setState(() {
        _errorMessage = null;
        _isInitializing = true;
        if (fallback != null) {
          debugPrint('[PlayerScreen] Switching to fallback address (.ts)');
          _currentStreamUrl = fallback;
        }
      });
      _openRetryTimer = Timer(delay, _reopenAfterFailure);
      return;
    }

    setState(() {
      _isInitializing = false;
      _errorMessage = message;
    });
  }

  /// Tears the failed engine down completely before opening again, so a retry
  /// never adds a second connection of our own on top of the one the provider
  /// is still counting.
  Future<void> _reopenAfterFailure() async {
    _supersedeOpen();
    _cancelSubscriptions();
    _historyTimer?.cancel();
    try {
      await _backend?.stop();
      await _backend?.dispose();
    } catch (_) {}
    _backend = null;
    if (mounted) {
      _initPlayer();
    }
  }

  void _retryPlayback() async {
    _supersedeOpen();
    _openRetryTimer?.cancel();
    _openAttempt = 0;
    _cancelSubscriptions();
    _historyTimer?.cancel();
    try {
      await _backend?.stop();
      await _backend?.dispose();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _backend = null;
      });
    }

    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      _initPlayer();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Double Tap Gestures for Seek
  // ═══════════════════════════════════════════════════════════════════════════

  void _onDoubleTapLeft() {
    _seekRelative(-10);
    setState(() => _showLeftSeek = true);
    _leftSeekTimer?.cancel();
    _leftSeekTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showLeftSeek = false);
    });
  }

  void _onDoubleTapRight() {
    _seekRelative(10);
    setState(() => _showRightSeek = true);
    _rightSeekTimer?.cancel();
    _rightSeekTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showRightSeek = false);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Lock Screen
  // ═══════════════════════════════════════════════════════════════════════════

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _showControls = false;
      } else {
        _showControls = true;
        _startHideTimer();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Cleanup
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _stopAndDispose() async {
    _historyTimer?.cancel();
    _hideTimer?.cancel();
    _leftSeekTimer?.cancel();
    _rightSeekTimer?.cancel();
    _seekGraceTimer?.cancel();
    _saveCurrentPosition(); // Save exact position on exit
    // After the save, so its guard still sees an open that never got going.
    _supersedeOpen();
    _openRetryTimer?.cancel();
    await _restoreWindowOnExit();
    _cancelSubscriptions();
    try {
      await _backend?.stop();
    } catch (_) {}
    try {
      await _backend?.dispose();
    } catch (_) {}
    _backend = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAndDispose();
    _brightnessSubscription?.cancel();
    VolumeController.instance.removeListener();
    WakelockPlus.disable(); // Allow screen to turn off again
    // Bring the status bar back now that we're leaving the watching
    // experience. The TV flavor's entry point (main_tv.dart) locks the whole
    // app landscape at startup — forcing portrait here on the way out fought
    // that and briefly rotated the whole app vertical before the OS caught
    // up, on top of being simply wrong for a TV, which has no orientation to
    // begin with. The phone flavor still restores portrait here so the rest
    // of the app behaves as before.
    if (!kIsTv) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Time Formatting
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Quality Info
  // ═══════════════════════════════════════════════════════════════════════════

  String get _qualityLabel {
    final h = _videoHeight;
    if (h == null || h == 0) return '';
    final label = h >= 1080
        ? '1080P'
        : h >= 720
        ? '720P'
        : h >= 480
        ? '480P'
        : '${h}P';
    return label;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Aspect Ratio — always the video's natural aspect ratio.
  // ═══════════════════════════════════════════════════════════════════════════

  double get _currentAspectRatio {
    if (_videoWidth != null &&
        _videoHeight != null &&
        _videoWidth! > 0 &&
        _videoHeight! > 0) {
      return _videoWidth! / _videoHeight!;
    }
    return 16 / 9;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final appDirection = Directionality.of(context);
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) await _stopAndDispose();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handlePlayerKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Video Layer ──
              _buildVideoLayer(),

              // ── Swipe Indicator (touchscreen only — see _buildVideoLayer) ──
              if (!kIsTvRemote && _indicatorMessage.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _indicatorMessage,
                        style: AppType.display(Colors.white),
                      ),
                    ),
                  ),
                ),

              // ── Double-tap zones (always active when unlocked) ──
              if (!_isLocked) _buildDoubleTapZones(),

              // ── Seek Feedback Overlays ──
              if (_showLeftSeek) _buildSeekFeedback(isLeft: true),
              if (_showRightSeek) _buildSeekFeedback(isLeft: false),

              // ── Lock indicator (when locked, tap to show unlock button) ──
              if (_isLocked) _buildLockOverlay(isArabic),

              // ── Controls Overlay ──
              if (_showControls && !_isLocked)
                _buildControlsOverlay(appDirection, isArabic),

              // ── Loading / Error / Buffering States ──
              if (_isInitializing) _buildLoading(isArabic),
              if (_isBuffering && !_isInitializing) _buildBuffering(),
              if (_errorMessage != null) _buildError(_errorMessage!, isArabic),

              // ── First-Run Gesture Tutorial (topmost, blocks interaction) ──
              if (_showTutorial) _buildGestureTutorial(isArabic),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Video Layer ───────────────────────────────────────────────────────────

  Widget _buildVideoLayer() {
    final backend = _backend;
    if (backend == null) {
      return Container(color: Colors.black);
    }

    final aspectRatio = _currentAspectRatio;

    final Widget videoWidget = Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: backend.buildVideoWidget(
          key: ValueKey(_currentStreamUrl),
          aspectRatio: aspectRatio,
        ),
      ),
    );

    // An actual remote has no touchscreen, so swipe-to-adjust brightness/
    // volume can never fire — skip wrapping in the drag-gesture detector
    // entirely rather than carry a dead GestureDetector around the video.
    // iPad (kIsTv but not kIsTvRemote) does have a touchscreen and keeps it.
    if (kIsTvRemote) return videoWidget;

    return GestureDetector(
      onVerticalDragStart: (details) async {
        _dragStartY = details.globalPosition.dy;
        if (details.globalPosition.dx < MediaQuery.of(context).size.width / 2) {
          // Left side: Brightness
          try {
            _startBrightness = await ScreenBrightness().current;
          } catch (e) {
            _startBrightness = 0.5;
          }
        } else {
          // Right side: Volume
          try {
            _startVolume = await VolumeController.instance.getVolume();
          } catch (e) {
            _startVolume = 0.5;
          }
        }
      },
      onVerticalDragUpdate: (details) {
        if (_dragStartY == null) return;
        final delta = (_dragStartY! - details.globalPosition.dy) / 200.0;

        if (details.globalPosition.dx < MediaQuery.of(context).size.width / 2) {
          // Brightness
          if (_startBrightness != null) {
            double newBrightness = (_startBrightness! + delta).clamp(0.0, 1.0);
            try {
              ScreenBrightness().setScreenBrightness(newBrightness);
              if (mounted) setState(() => _currentBrightness = newBrightness);
              _showIndicator(
                Icons.brightness_6_rounded,
                '${(newBrightness * 100).toInt()}%',
              );
            } catch (e) {}
          }
        } else {
          // Volume
          if (_startVolume != null) {
            double newVolume = (_startVolume! + delta).clamp(0.0, 1.0);
            try {
              VolumeController.instance.setVolume(newVolume);
              VolumeController.instance.showSystemUI = false;
              if (mounted) setState(() => _currentVolume = newVolume);
              _showIndicator(
                newVolume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                '${(newVolume * 100).toInt()}%',
              );
            } catch (e) {}
          }
        }
      },
      onVerticalDragEnd: (_) {
        _dragStartY = null;
        _startVolume = null;
        _startBrightness = null;
        _indicatorTimer = Timer(const Duration(seconds: 1), () {
          if (mounted) setState(() => _indicatorMessage = '');
        });
      },
      child: videoWidget,
    );
  }

  void _showIndicator(IconData icon, String text) {
    _indicatorTimer?.cancel();
    setState(() {
      _indicatorMessage = text;
      _showControls = false;
    });
    _indicatorTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _indicatorMessage = '');
    });
  }

  // ─── Double Tap Zones ──────────────────────────────────────────────────────

  Widget _buildDoubleTapZones() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          // Left half — double tap to rewind
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
              onDoubleTap: _onDoubleTapLeft,
              child: const SizedBox.expand(),
            ),
          ),
          // Right half — double tap to forward
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
              onDoubleTap: _onDoubleTapRight,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Seek Feedback Ripple ──────────────────────────────────────────────────

  Widget _buildSeekFeedback({required bool isLeft}) {
    return Positioned(
      left: isLeft ? 40 : null,
      right: isLeft ? null : 40,
      top: 0,
      bottom: 0,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: 1.0,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isLeft
                      ? Icons.fast_rewind_rounded
                      : Icons.fast_forward_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(height: 2),
                Text('10s', style: AppType.caption(Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Lock Overlay ──────────────────────────────────────────────────────────

  Widget _buildLockOverlay(bool isArabic) {
    return GestureDetector(
      onTap: () {
        // Show unlock button temporarily
        setState(() => _showControls = true);
        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showControls = false);
        });
      },
      behavior: HitTestBehavior.translucent,
      child: _showControls
          ? Container(
              color: Colors.black26,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildControlButton(
                    icon: Icons.lock_rounded,
                    onTap: _toggleLock,
                    tooltip: isArabic ? 'فتح القفل' : 'Unlock',
                  ),
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTROLS OVERLAY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildControlsOverlay(TextDirection appDirection, bool isArabic) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: _showControls ? 1.0 : 0.0,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xBB000000),
                Colors.transparent,
                Colors.transparent,
                Color(0xBB000000),
              ],
              stops: [0.0, 0.25, 0.75, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── Top Bar ──
                _buildTopBar(isArabic),

                Expanded(
                  child: Row(
                    children: [
                      // Brightness Sidebar — needs a touchscreen to drag.
                      // On an actual remote, volume/brightness are handled
                      // by the TV/remote itself, not the app; iPad has none
                      // of that, so it keeps this like a phone does.
                      if (!kIsTvRemote)
                        _buildVerticalSlider(
                          value: _currentBrightness,
                          icon: Icons.brightness_6_rounded,
                          onChanged: (val) {
                            setState(() => _currentBrightness = val);
                            ScreenBrightness().setScreenBrightness(val);
                            _resetHideTimer();
                          },
                        ),

                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Spacer(),
                            Directionality(
                              textDirection: appDirection,
                              child: _buildCenterTitle(),
                            ),
                            const Spacer(),
                            _buildCenterControls(),
                            const Spacer(),
                          ],
                        ),
                      ),

                      // Volume Sidebar — see the brightness one above.
                      if (!kIsTvRemote)
                        _buildVerticalSlider(
                          value: _currentVolume,
                          icon: Icons.volume_up_rounded,
                          onChanged: (val) {
                            setState(() => _currentVolume = val);
                            VolumeController.instance.setVolume(val);
                            VolumeController.instance.showSystemUI = false;
                            _resetHideTimer();
                          },
                        ),
                    ],
                  ),
                ),

                // ── TV Transport Row (rewind/play/forward/prev-next episode) ──
                // Remote-only: it exists because a remote has no on-screen
                // buttons to tap (see _buildCenterControls's kIsTvRemote
                // branch below) — iPad gets the full phone-style center row
                // instead, so it doesn't also need this separate row.
                if (kIsTvRemote && !widget.isLive) _buildTvTransportRow(),

                // ── Seek Bar ──
                if (!widget.isLive) _buildSeekBar(),

                // ── Bottom Controls ──
                _buildBottomControls(isArabic),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalSlider({
    required double value,
    required IconData icon,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          SizedBox(
            height: 160, // Medium-length bar rather than filling the screen.
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 6,
                  activeTrackColor: Theme.of(context).primaryColor,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Theme.of(
                    context,
                  ).primaryColor.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: value.clamp(0.0, 1.0),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(value * 100).toInt()}%',
            style: AppType.cardTitle(Colors.white),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar ───────────────────────────────────────────────────────────────

  /// Whether the window is currently fullscreen. Desktop only; always false
  /// elsewhere, where the app already owns the whole screen.
  bool _isFullScreen = false;

  /// True if this screen was the one that went fullscreen, so leaving the
  /// player restores the window — but a window the user had already made
  /// fullscreen themselves is left alone.
  bool _enteredFullScreenHere = false;

  Future<void> _toggleFullScreen() async {
    if (!kIsDesktop) {
      return;
    }
    try {
      final next = !await windowManager.isFullScreen();
      await windowManager.setFullScreen(next);
      // Windows keeps the caption bar in some setups even once the window is
      // fullscreen, which leaves a strip of window chrome over the video.
      // Hiding it explicitly makes fullscreen actually edge to edge, and it
      // is put back on the way out. macOS and Linux already drop their own
      // title bar as part of going fullscreen, so this is Windows only.
      if (Platform.isWindows) {
        await windowManager.setTitleBarStyle(
          next ? TitleBarStyle.hidden : TitleBarStyle.normal,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isFullScreen = next;
        if (next) {
          _enteredFullScreenHere = true;
        }
      });
      _resetHideTimer();
    } catch (_) {
      // A window that refuses the change is not worth interrupting playback
      // for; the button simply does nothing.
    }
  }

  /// Puts the window back as it was, if this screen is what changed it.
  Future<void> _restoreWindowOnExit() async {
    if (!kIsDesktop || !_enteredFullScreenHere) {
      return;
    }
    try {
      await windowManager.setFullScreen(false);
      if (Platform.isWindows) {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      }
    } catch (_) {}
  }

  Widget _buildTopBar(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: () async {
              await _stopAndDispose();
              if (mounted) Navigator.of(context).pop();
            },
          ),

          // Quality badge
          if (_qualityLabel.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _qualityLabel,
                style: AppType.caption(Colors.white70),
              ),
            ),

          const Spacer(),

          // Desktop only: on a phone or a television the app is already
          // fullscreen, so there is nothing to toggle.
          if (kIsDesktop)
            IconButton(
              tooltip: _isFullScreen
                  ? (isArabic ? 'إنهاء ملء الشاشة' : 'Exit full screen')
                  : (isArabic ? 'ملء الشاشة' : 'Full screen'),
              icon: Icon(
                _isFullScreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
                size: 26,
              ),
              onPressed: _toggleFullScreen,
            ),
        ],
      ),
    );
  }

  // ─── Center Title ──────────────────────────────────────────────────────────

  Widget _buildCenterTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Text(
        _currentTitle,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.sans(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          shadows: [const Shadow(blurRadius: 8, color: Colors.black)],
        ),
      ),
    );
  }

  // ─── Center Controls (Rewind / Play / Forward) ─────────────────────────────

  Widget _buildCenterControls() {
    final hasPlaylist = widget.playlist != null && widget.playlist!.length > 1;
    // Live has nothing to skip within and nothing to seek through, so the
    // only meaningful transport control is play/pause — and with the
    // ±10s and prev/next buttons gone it sits centered on its own.
    // Changing channel is on D-pad left/right instead (see
    // _handlePlayerKeyEvent), which is how a TV remote does it anyway.
    final isLive = _currentIsLive;

    if (kIsTvRemote) {
      // An actual remote keeps only the big Play/Pause here — rewind/
      // forward/prev/next episode all live in the dedicated transport row
      // next to the seek bar instead (see _buildTvTransportRow), so this
      // stays the one control worth showing on its own regardless of where
      // the rest of the row's D-pad highlight currently is. iPad falls
      // through to the full row below, same as a phone.
      return _buildPlayPauseCircle();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isLive && hasPlaylist) ...[
          _buildControlButton(
            icon: Icons.skip_previous_rounded,
            onTap: _playPrevious,
            size: 36,
          ),
          const SizedBox(width: 24),
        ],

        if (!isLive) ...[
          // Rewind 10s
          _buildControlButton(
            icon: Icons.replay_10_rounded,
            onTap: () => _seekRelative(-10),
            size: 36,
          ),
          const SizedBox(width: 32),
        ],

        _buildPlayPauseCircle(),
        if (!isLive) ...[
          const SizedBox(width: 32),

          // Forward 10s
          _buildControlButton(
            icon: Icons.forward_10_rounded,
            onTap: () => _seekRelative(10),
            size: 36,
          ),
        ],

        if (!isLive && hasPlaylist) ...[
          const SizedBox(width: 24),
          _buildControlButton(
            icon: Icons.skip_next_rounded,
            onTap: _playNext,
            size: 36,
          ),
        ],
      ],
    );
  }

  /// The one filled control in the transport.
  ///
  /// White fill, black glyph, no glow. Fixed rather than themed because the
  /// player is always on true black — and the previous fill was #E50914,
  /// which is Netflix's own brand red, not this app's.
  Widget _buildPlayPauseCircle() {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.black,
          size: 40,
        ),
      ),
    );
  }

  // ─── TV Transport Row (rewind/play/forward/prev-episode/next-episode) ─────
  //
  // TV-only, VOD/series-only — live keeps its existing left/right-changes-
  // channel behavior untouched, and has nothing to seek or skip through
  // anyway. Sits just above the seek bar so Previous/Next Episode read as
  // part of the same "where am I in this thing" cluster as the timeline,
  // not as a separate floating group elsewhere on screen.
  //
  // Always visible whenever controls are (so Previous/Next Episode are
  // reachable via their dedicated remote skip buttons — see
  // _handlePlayerKeyEvent — even mid-playback), but only actually
  // *highlighted*/D-pad-navigable while paused: while playing, left/right
  // means seek, not "move along this row", so showing a highlight here at
  // the same time would visually promise navigation the remote isn't
  // actually performing right now.
  Widget _buildTvTransportRow() {
    if (_currentIsLive) return const SizedBox.shrink();
    final actions = _tvControlActions;
    final interactive = _isUserPaused;
    final highlighted = interactive ? _tvHighlightedControl(actions) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final action in actions) ...[
            _buildTvTransportButton(
              action,
              isHighlighted: action == highlighted,
            ),
            if (action != actions.last) const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }

  Widget _buildTvTransportButton(
    _TvControlAction action, {
    required bool isHighlighted,
  }) {
    final IconData icon;
    final VoidCallback onTap;
    switch (action) {
      case _TvControlAction.previous:
        icon = Icons.skip_previous_rounded;
        onTap = _playPrevious;
      case _TvControlAction.rewind:
        icon = Icons.replay_10_rounded;
        onTap = () => _seekRelative(-10);
      case _TvControlAction.playPause:
        icon = _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
        onTap = _togglePlayPause;
      case _TvControlAction.forward:
        icon = Icons.forward_10_rounded;
        onTap = () => _seekRelative(10);
      case _TvControlAction.next:
        icon = Icons.skip_next_rounded;
        onTap = _playNext;
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isHighlighted
              ? _playerAccent
              : Colors.white.withValues(alpha: 0.14),
          border: isHighlighted
              ? Border.all(color: Colors.white, width: 2)
              : null,
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: _playerAccent.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  // ─── Seek Bar ──────────────────────────────────────────────────────────────

  Widget _buildSeekBar() {
    final position = _position;
    final duration = _duration;
    final totalMs = duration.inMilliseconds.toDouble();
    final currentMs = position.inMilliseconds.toDouble();
    final progress = totalMs > 0 ? (currentMs / totalMs).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Current time
          SizedBox(
            width: 60,
            child: Text(
              _formatDuration(
                _isDraggingSeek
                    ? Duration(milliseconds: (_dragSeekValue * totalMs).toInt())
                    : position,
              ),
              style: AppType.caption(Colors.white70),
            ),
          ),

          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: _playerAccent,
                inactiveTrackColor: Colors.white24,
                thumbColor: _playerAccent,
                overlayColor: _playerAccent.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: _isDraggingSeek ? _dragSeekValue : progress,
                onChangeStart: (val) {
                  _isDraggingSeek = true;
                  _dragSeekValue = val;
                  _hideTimer?.cancel();
                },
                onChanged: (val) {
                  setState(() => _dragSeekValue = val);
                },
                onChangeEnd: (val) {
                  _isDraggingSeek = false;
                  final targetMs = (val * totalMs).toInt();
                  final target = Duration(milliseconds: targetMs);
                  _backend?.seek(target);
                  _watchSeek(target);
                  _startHideTimer();
                },
              ),
            ),
          ),

          // Total duration
          SizedBox(
            width: 60,
            child: Text(
              _formatDuration(duration),
              textAlign: TextAlign.end,
              style: AppType.caption(Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom Controls ───────────────────────────────────────────────────────

  Widget _buildBottomControls(bool isArabic) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          // Lock — a touch-only concept (guards against accidental taps
          // during playback); a D-pad remote has nothing accidental to
          // guard against, but a touchscreen does regardless of which
          // layout is showing, so this follows kIsTvRemote not kIsTv.
          if (!kIsTvRemote)
            _buildControlButton(
              icon: _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              onTap: _toggleLock,
              tooltip: _isLocked
                  ? (isArabic ? 'فتح القفل' : 'Unlock')
                  : (isArabic ? 'قفل' : 'Lock'),
            ),

          const Spacer(),

          // Rotate video — cycles Vertical / Horizontal Right / Horizontal
          // Left; meaningless on an actual remote-driven TV, which never
          // physically rotates and has no touch to reach this with anyway.
          // iPad keeps it like a phone (kIsTvRemote, not kIsTv — see Lock
          // above).
          if (!kIsTvRemote)
            _buildControlButton(
              icon: Icons.screen_rotation_rounded,
              onTap: _rotateVideo,
              tooltip: _rotationIndex == -1
                  ? (isArabic ? 'تدوير' : 'Rotate')
                  : '${isArabic ? 'تدوير' : 'Rotate'}: ${_rotationLabel(_rotationIndex, isArabic)}',
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 24,
    String? tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          onTap();
          _resetHideTimer();
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cycles the forced screen orientation through all three usable sides —
  /// Vertical → Horizontal Right → Horizontal Left → back to Vertical —
  /// locking the display to exactly that orientation regardless of how the
  /// device is physically held, until the user taps again.
  void _rotateVideo() {
    setState(() {
      _rotationIndex = (_rotationIndex + 1) % _rotationOrientations.length;
    });
    SystemChrome.setPreferredOrientations([
      _rotationOrientations[_rotationIndex],
    ]);
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
    _showQuickToast(
      isArabic
          ? 'تم التدوير: ${_rotationLabel(_rotationIndex, isArabic)}'
          : 'Rotated: ${_rotationLabels[_rotationIndex]}',
    );
  }

  void _showQuickToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppType.sans(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        margin: const EdgeInsets.only(bottom: 80, left: 40, right: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Loading, Buffering & Error States
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLoading(bool isArabic) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_playerAccent),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              // During an automatic retry (see _handlePlaybackFailure) say so,
              // with a count: a twelve-second wait behind a plain "Loading"
              // reads as the app having hung.
              _openAttempt > 0
                  ? (isArabic
                        ? 'جارٍ إعادة الاتصال... ($_openAttempt من ${_openRetryDelays.length})'
                        : 'Reconnecting... ($_openAttempt of ${_openRetryDelays.length})')
                  : widget.isLive
                  ? (isArabic
                        ? 'جارٍ الاتصال بالبث...'
                        : 'Connecting to stream...')
                  : (isArabic ? 'جارٍ تحميل الفيديو...' : 'Loading video...'),
              style: AppType.body(Colors.white54),
            ),
            // Live channels can hang connecting far longer than VOD (a dead
            // or overloaded channel, a slow panel) with no way to tell how
            // long it'll take — so unlike VOD loading, give an explicit way
            // out here instead of only relying on the remote's back key.
            // Automatic retries can run for twelve seconds too, so VOD gets
            // the same way out while one is in progress.
            if (widget.isLive || _openAttempt > 0) ...[
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: () async {
                  await _stopAndDispose();
                  if (mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.arrow_back, color: Colors.white54),
                label: Text(
                  isArabic ? 'رجوع' : 'Go Back',
                  style: AppType.body(Colors.white54),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBuffering() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_playerAccent),
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message, bool isArabic) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: _playerAccent, size: 56),
              const SizedBox(height: 20),
              Text(
                isArabic ? 'خطأ في التشغيل' : 'Playback Error',
                style: AppType.heading(Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppType.body(Colors.white60),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white54),
                    label: Text(
                      isArabic ? 'رجوع' : 'Go Back',
                      style: AppType.body(Colors.white54),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _retryPlayback,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    label: Text(
                      isArabic ? 'إعادة المحاولة' : 'Retry',
                      style: AppType.cardTitle(Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _playerAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // First-Run Gesture Tutorial
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGestureTutorial(bool isArabic) {
    return Positioned.fill(
      child: GestureDetector(
        // Absorb every gesture so it can't leak through to seek/controls
        // underneath — only the Skip button below dismisses this.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onVerticalDragStart: (_) {},
        onDoubleTap: () {},
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(),
                Text(
                  isArabic
                      ? 'التحكم بالسطوع والصوت'
                      : 'Control Brightness & Volume',
                  textAlign: TextAlign.center,
                  style: AppType.heading(Colors.white),
                ),
                const SizedBox(height: 32),
                IntrinsicHeight(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _buildTutorialHalf(
                          icon: Icons.brightness_6_rounded,
                          label: isArabic
                              ? 'مرر لأعلى أو لأسفل هنا\nلضبط السطوع'
                              : 'Swipe up or down here\nto adjust brightness',
                        ),
                      ),
                      Container(width: 1, color: Colors.white24),
                      Expanded(
                        child: _buildTutorialHalf(
                          icon: Icons.volume_up_rounded,
                          label: isArabic
                              ? 'مرر لأعلى أو لأسفل هنا\nلضبط الصوت'
                              : 'Swipe up or down here\nto adjust volume',
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: ElevatedButton(
                    onPressed: _dismissTutorial,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _playerAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      isArabic ? 'تخطي' : 'Skip',
                      style: AppType.cardTitle(Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTutorialHalf({required IconData icon, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white70, size: 26),
        const SizedBox(height: 2),
        Icon(icon, color: Colors.white, size: 40),
        const SizedBox(height: 2),
        Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.white70,
          size: 26,
        ),
        const SizedBox(height: 14),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppType.bodySmall(Colors.white),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SETTINGS SHEET
// ═══════════════════════════════════════════════════════════════════════════════
