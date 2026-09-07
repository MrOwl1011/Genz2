import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/player_backend.dart';
import '../services/player_backend_factory.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../widgets/state_view.dart';
import '../widgets/tv_focusable.dart';
import 'player_screen.dart';
import '../widgets/skeleton.dart';

class ChannelsScreen extends StatefulWidget {
  final XtreamCategory category;

  const ChannelsScreen({super.key, required this.category});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<XtreamLiveStream> _allChannels = [];
  List<XtreamLiveStream> _filtered = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  // Mini player state
  XtreamLiveStream? _currentChannel;
  PlayerBackend? _backend;
  bool _isPlayerLoading = false;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _disposePlayer();
    super.dispose();
  }

  /// Awaited in _playChannel (via await below) so a new backend isn't
  /// created while the previous one is still mid-teardown — stop()/dispose()
  /// are real async native calls, and firing them without awaiting let two
  /// player lifecycles overlap, which is why switching to a second channel
  /// in the mini-player would silently fail to load after the first one
  /// played fine.
  Future<void> _disposePlayer() async {
    final backend = _backend;

    if (mounted) {
      setState(() {
        _backend = null;
      });
    } else {
      _backend = null;
    }

    try {
      await backend?.stop();
      await backend?.dispose();
    } catch (_) {}
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final content = context.read<ContentProvider>();
      final channels = await content.getLiveStreams(
        categoryId: widget.category.categoryId,
      );
      if (mounted) {
        setState(() {
          _allChannels = channels;
          _filtered = channels;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _onSearch(String query) {
    setState(() {
      _filtered = query.isEmpty
          ? _allChannels
          : _allChannels
                .where(
                  (c) => c.name.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
    });
  }

  Future<void> _playChannel(XtreamLiveStream channel) async {
    if (_currentChannel?.streamId == channel.streamId) {
      return; // Already playing
    }

    await _disposePlayer();
    if (!mounted) return;

    setState(() {
      _currentChannel = channel;
      _isPlayerLoading = true;
    });

    PlayerBackend? backend;
    try {
      final content = context.read<ContentProvider>();
      final url = channel.streamUrl(
        content.baseUrl,
        content.username,
        content.password,
      );

      // Assign the backend (and rebuild) *before* awaiting open() below —
      // engines like VLC only start initializing once their video widget
      // has actually mounted, so the widget needs to be in the tree first.
      backend = createPlayerBackend();
      if (mounted) setState(() => _backend = backend);

      await backend.open(
        url: url,
        httpHeaders: const {'User-Agent': 'NX-IPTV/1.0'},
        autoPlay: true,
      );

      // Bounded wait for the engine to report signs of life before dropping
      // the loading indicator — see PlayerScreen._initPlayer for why (VLC's
      // native init can finish after open() already returned).
      int readyWaits = 0;
      while (backend.duration.inMilliseconds == 0 &&
          backend.position.inMilliseconds == 0 &&
          readyWaits < 100 &&
          mounted) {
        await Future.delayed(const Duration(milliseconds: 50));
        readyWaits++;
      }

      if (mounted) {
        setState(() => _isPlayerLoading = false);
      }
    } catch (e) {
      debugPrint('[ChannelsScreen] Mini player error: $e');
      try {
        await backend?.dispose();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isPlayerLoading = false;
          _currentChannel = null;
          _backend = null;
        });
        final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'فشل التشغيل: ${e.toString().replaceFirst("Exception: ", "")}'
                  : 'Failed to play: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: context.colors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _disposePlayer();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.backgroundGradient,
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: colors.ink,
                          size: 20,
                        ),
                        onPressed: () {
                          _disposePlayer();
                          Navigator.of(context).pop();
                        },
                      ),
                      Expanded(
                        child: Text(
                          '- ${widget.category.categoryName.toUpperCase()}',
                          style: AppType.sans(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: colors.ink,
                            letterSpacing: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Search — favoriting now happens per-channel in the list below.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: colors.ink,
                          size: 18,
                        ),
                        onPressed: () {
                          _disposePlayer();
                          Navigator.of(context).pop();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: colors.border,
                              width: 1.5,
                            ),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearch,
                            style: AppType.body(colors.ink),
                            decoration: InputDecoration(
                              hintText: isArabic ? 'بحث' : 'Search',
                              hintStyle: AppType.body(
                                colors.ink.withValues(alpha: 0.3),
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: colors.ink.withValues(alpha: 0.38),
                                size: 20,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Mini Player — intentionally always-dark video chrome, same
                // treatment as the fullscreen Player (see player_screen.dart);
                // it overlays live video content, not themed page chrome.
                if (_currentChannel != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Video area
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              children: [
                                _backend != null
                                    ? Stack(
                                        children: [
                                          _backend!.buildVideoWidget(
                                            aspectRatio: 16 / 9,
                                          ),
                                          // Channel name overlay
                                          Positioned(
                                            top: 8,
                                            left: 12,
                                            child: Text(
                                              _currentChannel!.name,
                                              style: AppType.sans(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                shadows: [
                                                  const Shadow(
                                                    blurRadius: 4,
                                                    color: Colors.black,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // Channel logo overlay
                                          if (_currentChannel!
                                              .streamIcon
                                              .isNotEmpty)
                                            Positioned(
                                              top: 8,
                                              right: 12,
                                              child: CachedNetworkImage(
                                                imageUrl:
                                                    _currentChannel!.streamIcon,
                                                width: 40,
                                                height: 40,
                                                errorWidget: (_, _, _) =>
                                                    const SizedBox.shrink(),
                                              ),
                                            ),
                                          // Fullscreen button
                                          Positioned(
                                            bottom: 8,
                                            right: 8,
                                            child: GestureDetector(
                                              onTap: () {
                                                final content = context
                                                    .read<ContentProvider>();
                                                final url = _currentChannel!
                                                    .streamUrl(
                                                      content.baseUrl,
                                                      content.username,
                                                      content.password,
                                                    );

                                                final initialIndex = _filtered
                                                    .indexWhere(
                                                      (c) =>
                                                          c.streamId ==
                                                          _currentChannel!
                                                              .streamId,
                                                    );
                                                final playlist = _filtered.map((
                                                  c,
                                                ) {
                                                  return {
                                                    'url': c.streamUrl(
                                                      content.baseUrl,
                                                      content.username,
                                                      content.password,
                                                    ),
                                                    'title': c.name,
                                                    'coverUrl': c.streamIcon,
                                                    'isLive': true,
                                                    'mediaId': c.streamId
                                                        .toString(),
                                                    'mediaType': MediaType.live,
                                                    'rawMediaData': c.toJson(),
                                                  };
                                                }).toList();

                                                _disposePlayer();
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        PlayerScreen(
                                                          streamUrl: url,
                                                          title:
                                                              _currentChannel!
                                                                  .name,
                                                          coverUrl:
                                                              _currentChannel!
                                                                  .streamIcon,
                                                          isLive: true,
                                                          mediaId:
                                                              _currentChannel!
                                                                  .streamId
                                                                  .toString(),
                                                          mediaType:
                                                              MediaType.live,
                                                          rawMediaData:
                                                              _currentChannel!
                                                                  .toJson(),
                                                          playlist: playlist,
                                                          initialIndex:
                                                              initialIndex,
                                                        ),
                                                  ),
                                                );
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.fullscreen_rounded,
                                                  color: Colors.white,
                                                  size: 24,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Container(color: Colors.black),
                                if (_isPlayerLoading)
                                  Container(
                                    color: Colors.black,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              colors.brandPrimary,
                                            ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),

                // Channel List
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';
    if (_isLoading) {
      return const SkeletonList();
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              color: colors.ink.withValues(alpha: 0.24),
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppType.body(colors.ink.withValues(alpha: 0.54)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadChannels,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.brandPrimary,
              ),
              child: Text(
                isArabic ? 'إعادة المحاولة' : 'Retry',
                style: AppType.body(Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    if (_filtered.isEmpty) {
      return StateView(
        icon: Icons.tv_off_rounded,
        title: isArabic ? 'لا توجد قنوات' : 'No channels',
        message: isArabic
            ? 'لم يُرجع مزودك أي قناة هنا. جرّب فئة أخرى.'
            : 'Your provider returned no channels here. Try another category.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final ch = _filtered[index];
        final isPlaying = _currentChannel?.streamId == ch.streamId;
        return _ChannelTile(
          channel: ch,
          isPlaying: isPlaying,
          onTap: () => _playChannel(ch),
        );
      },
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final XtreamLiveStream channel;
  final bool isPlaying;
  final VoidCallback onTap;

  const _ChannelTile({
    required this.channel,
    required this.onTap,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final userPrefs = context.watch<UserPrefsProvider>();
    final favoriteId = channel.streamId.toString();
    final isFav = userPrefs.isFavorite(favoriteId);
    final isArabic = userPrefs.locale == 'ar';
    return TvFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 72,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            // The channel on air gets a leading bar rather than a tinted
            // fill: a bar is scannable down a long list, a wash is not.
            Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(
                color: isPlaying ? colors.brandPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 11),
            // Logo as an inset tile, not an edge-to-edge strip — channel
            // logos are artwork on a plate, and cropping them to the row's
            // full height cuts most of them.
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 56,
                height: 56,
                color: colors.surfaceMuted,
                child: channel.streamIcon.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: channel.streamIcon,
                        fit: BoxFit.contain,
                        placeholder: (_, _) => Icon(
                          Icons.tv_rounded,
                          color: colors.ink.withValues(alpha: 0.24),
                          size: 22,
                        ),
                        errorWidget: (_, _, _) => Icon(
                          Icons.tv_rounded,
                          color: colors.ink.withValues(alpha: 0.24),
                          size: 22,
                        ),
                      )
                    : Icon(
                        Icons.tv_rounded,
                        color: colors.ink.withValues(alpha: 0.24),
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.cardTitle(colors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isArabic ? 'لا توجد معلومات' : 'No Information',
                    style: AppType.caption(colors.ink.withValues(alpha: 0.38)),
                  ),
                ],
              ),
            ),
            // Per-channel favorite toggle.
            IconButton(
              icon: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav
                    ? colors.brandPrimary
                    : colors.ink.withValues(alpha: 0.38),
                size: 20,
              ),
              onPressed: () {
                userPrefs.toggleFavorite(
                  id: favoriteId,
                  title: channel.name,
                  posterUrl: channel.streamIcon,
                  type: MediaType.live,
                  rawData: channel.toJson(),
                );
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
