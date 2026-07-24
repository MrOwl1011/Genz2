import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/player_backend.dart';
import '../services/player_backend_factory.dart';
import '../services/player_engine.dart';
import 'player_screen.dart';

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
  late final PlayerEngine _engine;
  XtreamLiveStream? _currentChannel;
  PlayerBackend? _backend;
  bool _isPlayerLoading = false;

  @override
  void initState() {
    super.initState();
    _engine = context.read<UserPrefsProvider>().playerEngine;
    _loadChannels();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _disposePlayer();
    super.dispose();
  }

  void _disposePlayer() {
    final backend = _backend;

    if (mounted) {
      setState(() {
        _backend = null;
      });
    } else {
      _backend = null;
    }

    try {
      backend?.stop();
      backend?.dispose();
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
    if (_currentChannel?.streamId == channel.streamId)
      return; // Already playing

    _disposePlayer();

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
      backend = createPlayerBackend(_engine);
      if (mounted) setState(() => _backend = backend);

      await backend.open(
        url: url,
        httpHeaders: const {'User-Agent': 'NX-IPTV/1.0'},
        autoPlay: true,
      );

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to play: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: const Color(0xFFE50914),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userPrefs = context.watch<UserPrefsProvider>();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _disposePlayer();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF220306), Color(0xFF0C0002), Color(0xFF000000)],
              stops: [0.0, 0.6, 1.0],
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
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
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
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
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

                // Search + Like
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
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
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: const Color(0xFF200306),
                              width: 1.5,
                            ),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearch,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search',
                              hintStyle: GoogleFonts.outfit(
                                color: Colors.white30,
                                fontSize: 14,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.white38,
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
                      const SizedBox(width: 8),
                      // Like/Favorite button for the current category
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: IconButton(
                          icon: Icon(
                            userPrefs.isFavorite(
                                  'live_cat_${widget.category.categoryId}',
                                )
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color:
                                userPrefs.isFavorite(
                                  'live_cat_${widget.category.categoryId}',
                                )
                                ? const Color(0xFFE50914)
                                : Colors.white70,
                            size: 22,
                          ),
                          onPressed: () {
                            userPrefs.toggleFavorite(
                              id: 'live_cat_${widget.category.categoryId}',
                              title: widget.category.categoryName,
                              posterUrl: '',
                              type: MediaType.live,
                              rawData: {
                                'category_id': widget.category.categoryId,
                                'category_name': widget.category.categoryName,
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Mini Player
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
                                          style: GoogleFonts.outfit(
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
                                                      _currentChannel!.streamId,
                                                );
                                            final playlist = _filtered.map((c) {
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
                                                builder: (_) => PlayerScreen(
                                                  streamUrl: url,
                                                  title: _currentChannel!.name,
                                                  coverUrl: _currentChannel!
                                                      .streamIcon,
                                                  isLive: true,
                                                  mediaId: _currentChannel!
                                                      .streamId
                                                      .toString(),
                                                  mediaType: MediaType.live,
                                                  rawMediaData: _currentChannel!
                                                      .toJson(),
                                                  playlist: playlist,
                                                  initialIndex: initialIndex,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.6,
                                              ),
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
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Color(0xFFE50914),
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white54),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadChannels,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.outfit(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Text(
          'No channels found.',
          style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16),
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 72,
        decoration: BoxDecoration(
          color: isPlaying
              ? const Color(0xFF3A1015)
              : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPlaying
                ? const Color(0xFFE50914)
                : const Color(0xFF2A0508),
            width: isPlaying ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Logo
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: channel.streamIcon.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: channel.streamIcon,
                      width: 80,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 80,
                        color: Colors.white10,
                        child: const Icon(
                          Icons.tv_rounded,
                          color: Colors.white24,
                          size: 24,
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 80,
                        color: Colors.white10,
                        child: const Icon(
                          Icons.tv_rounded,
                          color: Colors.white24,
                          size: 24,
                        ),
                      ),
                    )
                  : Container(
                      width: 80,
                      color: Colors.white10,
                      child: const Icon(
                        Icons.tv_rounded,
                        color: Colors.white24,
                        size: 24,
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
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'No Information',
                    style: GoogleFonts.outfit(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
