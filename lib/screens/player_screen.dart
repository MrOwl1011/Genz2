// Professional IPTV Player Screen with custom controls overlay.
// Replaces Chewie controls with a fully custom UI matching modern IPTV players.
// Features: auto-hide controls, double-tap seek, settings sheet, lock screen,
// quality display, seek bar, and right-side action buttons.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import '../providers/user_prefs_provider.dart';

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

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ─── Video Controller ──────────────────────────────────────────────────────
  Player? _player;
  VideoController? _videoController;
  bool _isInitializing = true;
  bool _isBuffering = false;
  String? _errorMessage;
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
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int? _videoWidth;
  int? _videoHeight;

  // ─── Controls State ────────────────────────────────────────────────────────
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideTimer;
  bool _isDraggingSeek = false;
  double _dragSeekValue = 0.0;
  int _lastSaveTime = 0;

  // ─── Settings State ────────────────────────────────────────────────────────
  double _playbackSpeed = 1.0;
  int _aspectRatioIndex = 0; // 0=Fit, 1=Fill, 2=16:9, 3=4:3
  static const List<String> _aspectRatioLabels = ['Fit', 'Fill', '16:9', '4:3'];

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _initVolumeAndBrightness();
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
    _brightnessSubscription = ScreenBrightness().onCurrentBrightnessChanged.listen((brightness) {
      if (mounted) setState(() => _currentBrightness = brightness);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Player Initialization
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _initPlayer() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
      _isBuffering = false;
    });

    try {
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024, // 32 MB buffer for streaming
        ),
      );

      _videoController = VideoController(_player!);

      // Subscribe to player streams for reactive state updates
      _subscribeToPlayerStreams();

      // Open the media strictly without playing to prevent overriding position
      await _player!.open(
        Media(
          _currentStreamUrl,
          httpHeaders: const {'User-Agent': 'NX-IPTV/1.0'},
        ),
        play: false,
      );

      // Restore exact position for non-live content
      if (!_currentIsLive) {
        int targetPos = 0;
        if (_currentMediaId != null && mounted) {
          targetPos = context.read<UserPrefsProvider>().getHistoryPositionMilliseconds(_currentMediaId!);
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
          while (_duration.inMilliseconds == 0 && durationWaits < 100 && mounted) {
            await Future.delayed(const Duration(milliseconds: 50));
            durationWaits++;
          }
          
          debugPrint('[Player History] Player Initialized: ${_duration.inMilliseconds > 0}');

          // CRITICAL FIX FOR ANDROID: Start playing before seeking. 
          // If play is false, libmpv/ExoPlayer on Android may ignore the seek command 
          // or reset to the first keyframe because the codec is not fully initialized.
          await _player!.play();

          // Wait until the player actually starts progressing (position > 0)
          // This guarantees that the native engine is fully prepared and actively playing,
          // so it won't reset our seek back to 0.
          int playWaits = 0;
          while (_player!.state.position.inMilliseconds == 0 && playWaits < 40 && mounted) {
            await Future.delayed(const Duration(milliseconds: 50));
            playWaits++;
          }

          // Issue the exact seek
          debugPrint('[Player History] Seek Requested: $targetPos ms');
          await _player!.seek(Duration(milliseconds: targetPos));
          debugPrint('[Player History] Seek Completed: $targetPos ms');

          // Strict polling loop to verify the engine actually jumped to the position
          int seekWaits = 0;
          while (seekWaits < 100 && mounted) {
            final currentPos = _player!.state.position.inMilliseconds;
            // Allow a 1.5 second variance (keyframes can snap position slightly)
            if ((currentPos - targetPos).abs() <= 1500 || currentPos >= targetPos) {
              break;
            }
            await Future.delayed(const Duration(milliseconds: 50));
            seekWaits++;
          }

          debugPrint('[Player History] Current Position After Seek: ${_player!.state.position.inMilliseconds} ms');
        }
      }
      
      // ONLY start playback after the seek verification completes (safe to call again)
      await _player!.play();

      _startHideTimer();

      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      debugPrint('[PlayerScreen] Playback init error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// Subscribe to all player state streams for reactive UI updates.
  void _subscribeToPlayerStreams() {
    _playingSubscription = _player!.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    _positionSubscription = _player!.stream.position.listen((position) {
      if (mounted && !_isDraggingSeek) {
        setState(() => _position = position);
        // Continuously update position (throttle to avoid UI jank)
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastSaveTime > 3000) {
          _saveCurrentPosition();
          _lastSaveTime = now;
        }
      }
    });

    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });

    _bufferingSubscription = _player!.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _errorSubscription = _player!.stream.error.listen((error) {
      if (error.isNotEmpty && mounted) {
        debugPrint('[PlayerScreen] Playback error: $error');
        setState(() => _errorMessage = error);
      }
    });

    _completedSubscription = _player!.stream.completed.listen((completed) {
      if (completed && mounted) {
        // Auto-play next in playlist only for TV series if enabled
        if (_currentMediaType == MediaType.series) {
          final autoPlayEnabled = context.read<UserPrefsProvider>().autoPlayNextEpisode;
          if (autoPlayEnabled &&
              widget.playlist != null &&
              _currentIndex < widget.playlist!.length - 1) {
            _playNext();
          }
        }
      }
    });

    _widthSubscription = _player!.stream.width.listen((width) {
      if (mounted) setState(() => _videoWidth = width);
    });

    _heightSubscription = _player!.stream.height.listen((height) {
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
    if (_player == null || !mounted) return;
    if (_currentIsLive ||
        _currentMediaId == null ||
        _currentMediaType == null ||
        _currentRawMediaData == null) {
      return;
    }

    final position = _position.inMilliseconds;
    final duration = _duration.inMilliseconds;

    if (position > 0) {
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
        index >= widget.playlist!.length)
      return;

    // Save current position before switching
    _saveCurrentPosition();

    _cancelSubscriptions();
    _historyTimer?.cancel();
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    
    if (mounted) {
      setState(() {
        _player = null;
        _videoController = null;
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
    if (widget.playlist != null &&
        _currentIndex < widget.playlist!.length - 1) {
      _playIndex(_currentIndex + 1);
    }
  }

  void _playPrevious() {
    if (widget.playlist != null && _currentIndex > 0) {
      _playIndex(_currentIndex - 1);
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

  void _togglePlayPause() {
    if (_player == null) return;
    _player!.playOrPause();
    _resetHideTimer();
    if (_isPlaying) {
      _saveCurrentPosition();
    }
  }

  void _seekRelative(int seconds) {
    if (_player == null) return;
    final current = _position;
    final duration = _duration;
    final target = current + Duration(seconds: seconds);
    _player!.seek(
      target < Duration.zero
          ? Duration.zero
          : (target > duration ? duration : target),
    );
    _resetHideTimer();
  }

  void _retryPlayback() async {
    _cancelSubscriptions();
    _historyTimer?.cancel();
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    
    if (mounted) {
      setState(() {
        _player = null;
        _videoController = null;
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
    _saveCurrentPosition(); // Save exact position on exit
    _cancelSubscriptions();
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _videoController = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAndDispose();
    _brightnessSubscription?.cancel();
    VolumeController.instance.removeListener();
    WakelockPlus.disable(); // Allow screen to turn off again
    // Restore portrait + keep immersive mode (don't reveal system bars)
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
  // Aspect Ratio
  // ═══════════════════════════════════════════════════════════════════════════

  double? get _currentAspectRatio {
    switch (_aspectRatioIndex) {
      case 1:
        return null; // Fill — stretch to fit
      case 2:
        return 16 / 9;
      case 3:
        return 4 / 3;
      default: // Fit — natural aspect ratio
        if (_videoWidth != null &&
            _videoHeight != null &&
            _videoWidth! > 0 &&
            _videoHeight! > 0) {
          return _videoWidth! / _videoHeight!;
        }
        return 16 / 9;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final appDirection = Directionality.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) await _stopAndDispose();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Video Layer ──
            _buildVideoLayer(),

            // ── Swipe Indicator ──
            if (_indicatorMessage.isNotEmpty)
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
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
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
            if (_isLocked) _buildLockOverlay(),

            // ── Controls Overlay ──
            if (_showControls && !_isLocked) _buildControlsOverlay(appDirection),

            // ── Loading / Error / Buffering States ──
            if (_isInitializing) _buildLoading(),
            if (_isBuffering && !_isInitializing) _buildBuffering(),
            if (_errorMessage != null) _buildError(_errorMessage!),
          ],
        ),
      ),
    );
  }

  // ─── Video Layer ───────────────────────────────────────────────────────────

  Widget _buildVideoLayer() {
    if (_videoController == null) {
      return Container(color: Colors.black);
    }

    final aspectRatio = _currentAspectRatio;

    Widget videoWidget;
    if (_aspectRatioIndex == 1) {
      // Fill mode — stretch video to fill screen
      videoWidget = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: (_videoWidth ?? 1920).toDouble(),
            height: (_videoHeight ?? 1080).toDouble(),
            child: Video(
              key: ValueKey(_currentStreamUrl),
              controller: _videoController!,
              controls: NoVideoControls,
            ),
          ),
        ),
      );
    } else {
      videoWidget = Center(
        child: AspectRatio(
          aspectRatio: aspectRatio ?? 16 / 9,
          child: Video(
            key: ValueKey(_currentStreamUrl),
            controller: _videoController!,
            controls: NoVideoControls,
          ),
        ),
      );
    }

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
                Text(
                  '10s',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Lock Overlay ──────────────────────────────────────────────────────────

  Widget _buildLockOverlay() {
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
                    tooltip: 'Unlock',
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

  Widget _buildControlsOverlay(TextDirection appDirection) {
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
                _buildTopBar(),

                Expanded(
                  child: Row(
                    children: [
                      // Brightness Sidebar
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

                      // Volume Sidebar
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

                // ── Seek Bar ──
                if (!widget.isLive) _buildSeekBar(),

                // ── Bottom Controls ──
                _buildBottomControls(),
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
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 16),
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: Theme.of(context).primaryColor,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: value.clamp(0.0, 1.0),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${(value * 100).toInt()}%',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
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
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          const Spacer(),

          // Right side vertical buttons
          _buildControlButton(
            icon: Icons.aspect_ratio_rounded,
            onTap: _cycleAspectRatio,
            tooltip: 'Aspect: ${_aspectRatioLabels[_aspectRatioIndex]}',
          ),
          const SizedBox(width: 4),
          _buildControlButton(
            icon: Icons.settings_rounded,
            onTap: _showSettingsSheet,
            tooltip: 'Settings',
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
        style: GoogleFonts.outfit(
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (hasPlaylist) ...[
          _buildControlButton(
            icon: Icons.skip_previous_rounded,
            onTap: _playPrevious,
            size: 36,
          ),
          const SizedBox(width: 24),
        ],

        // Rewind 10s
        _buildControlButton(
          icon: Icons.replay_10_rounded,
          onTap: () => _seekRelative(-10),
          size: 36,
        ),
        const SizedBox(width: 32),

        // Play/Pause
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE50914).withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE50914).withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
        ),
        const SizedBox(width: 32),

        // Forward 10s
        _buildControlButton(
          icon: Icons.forward_10_rounded,
          onTap: () => _seekRelative(10),
          size: 36,
        ),

        if (hasPlaylist) ...[
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
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: const Color(0xFFE50914),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFFE50914),
                overlayColor: const Color(0xFFE50914).withValues(alpha: 0.2),
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
                  _player?.seek(Duration(milliseconds: targetMs));
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
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom Controls ───────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          // Lock
          _buildControlButton(
            icon: _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            onTap: _toggleLock,
            tooltip: _isLocked ? 'Unlock' : 'Lock',
          ),

          const Spacer(),

          // Playback speed badge
          GestureDetector(
            onTap: _cyclePlaybackSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_playbackSpeed}x',
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const Spacer(),

          // Fullscreen indicator (already in fullscreen)
          _buildControlButton(
            icon: Icons.fullscreen_rounded,
            onTap: () {}, // Already fullscreen
            tooltip: 'Fullscreen',
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
        borderRadius: BorderRadius.circular(24),
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

  void _cycleAspectRatio() {
    setState(() {
      _aspectRatioIndex = (_aspectRatioIndex + 1) % _aspectRatioLabels.length;
    });
    _showQuickToast('Aspect Ratio: ${_aspectRatioLabels[_aspectRatioIndex]}');
  }

  void _cyclePlaybackSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIdx = speeds.indexOf(_playbackSpeed);
    final nextIdx = (currentIdx + 1) % speeds.length;
    setState(() => _playbackSpeed = speeds[nextIdx]);
    _player?.setRate(_playbackSpeed);
    _showQuickToast('Speed: ${_playbackSpeed}x');
  }

  void _showQuickToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        margin: const EdgeInsets.only(bottom: 80, left: 40, right: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSettingsSheet() {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SettingsSheet(
        playbackSpeed: _playbackSpeed,
        aspectRatioIndex: _aspectRatioIndex,
        aspectRatioLabels: _aspectRatioLabels,
        isLive: widget.isLive,
        onPlaybackSpeedChanged: (speed) {
          setState(() => _playbackSpeed = speed);
          _player?.setRate(speed);
        },
        onAspectRatioChanged: (index) {
          setState(() => _aspectRatioIndex = index);
        },
      ),
    ).then((_) => _startHideTimer());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Loading, Buffering & Error States
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLoading() {
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
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.isLive ? 'Connecting to stream...' : 'Loading video...',
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
            ),
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
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFE50914),
                size: 56,
              ),
              const SizedBox(height: 20),
              Text(
                'Playback Error',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white54),
                    label: Text(
                      'Go Back',
                      style: GoogleFonts.outfit(color: Colors.white54),
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
                      'Retry',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// SETTINGS SHEET
// ═══════════════════════════════════════════════════════════════════════════════

/// Bottom sheet for player settings: speed, aspect ratio, subtitles, etc.
class _SettingsSheet extends StatelessWidget {
  final double playbackSpeed;
  final int aspectRatioIndex;
  final List<String> aspectRatioLabels;
  final bool isLive;
  final ValueChanged<double> onPlaybackSpeedChanged;
  final ValueChanged<int> onAspectRatioChanged;

  const _SettingsSheet({
    required this.playbackSpeed,
    required this.aspectRatioIndex,
    required this.aspectRatioLabels,
    required this.isLive,
    required this.onPlaybackSpeedChanged,
    required this.onAspectRatioChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Settings',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  // Playback Speed
                  _buildSettingsSection(
                    context,
                    icon: Icons.speed_rounded,
                    title: 'Playback Speed',
                    value: '${playbackSpeed}x',
                    onTap: () => _showSpeedPicker(context),
                  ),

                  // Aspect Ratio
                  _buildSettingsSection(
                    context,
                    icon: Icons.aspect_ratio_rounded,
                    title: 'Aspect Ratio',
                    value: aspectRatioLabels[aspectRatioIndex],
                    onTap: () => _showAspectPicker(context),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFE50914), size: 24),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white38,
            size: 20,
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  void _showSpeedPicker(BuildContext context) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Playback Speed',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...speeds.map(
            (s) => ListTile(
              title: Text(
                '${s}x',
                style: GoogleFonts.outfit(
                  color: s == playbackSpeed
                      ? const Color(0xFFE50914)
                      : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: s == playbackSpeed
                  ? const Icon(Icons.check_rounded, color: Color(0xFFE50914))
                  : null,
              onTap: () {
                onPlaybackSpeedChanged(s);
                Navigator.pop(ctx);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showAspectPicker(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Aspect Ratio',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...List.generate(
            aspectRatioLabels.length,
            (i) => ListTile(
              title: Text(
                aspectRatioLabels[i],
                style: GoogleFonts.outfit(
                  color: i == aspectRatioIndex
                      ? const Color(0xFFE50914)
                      : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: i == aspectRatioIndex
                  ? const Icon(Icons.check_rounded, color: Color(0xFFE50914))
                  : null,
              onTap: () {
                onAspectRatioChanged(i);
                Navigator.pop(ctx);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
