import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/user_prefs_provider.dart';
import '../../screens/player_screen.dart';
import '../../services/player_backend.dart';
import '../../services/player_backend_factory.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_nav_bar.dart' show TvSection;
import '../widgets/tv_sidebar.dart';
import 'tv_search_screen.dart';
import 'tv_settings_screen.dart';

/// TV-native Live TV: categories, channels and a live preview together on
/// one screen, rather than the phone's two-screen drill-down — closer to
/// how a set-top channel browser works, and avoids a route push (with its
/// own player teardown/rebuild) for every single category tap.
///
/// [onSelectSection] lets the persistent nav bar jump straight to Movies or
/// Series without a "back" round trip through Home first.
class TvLiveScreen extends StatefulWidget {
  final ValueChanged<TvSection> onSelectSection;

  /// A remembered category id from a previous visit this session (see
  /// TvHomeScreen's _lastLiveCategoryId) — this screen is always a fresh
  /// push (never survives its own pop), so without this every visit reset
  /// to the very first category regardless of what the user was actually
  /// watching last. Preferred over the first category on load when present
  /// and still resolvable in the current category list; ignored otherwise.
  final String? initialCategoryId;

  /// Fired whenever the selected category changes, so the caller (only
  /// TvHomeScreen today) can remember it for the next visit.
  final ValueChanged<String>? onCategoryChanged;

  const TvLiveScreen({
    super.key,
    required this.onSelectSection,
    this.initialCategoryId,
    this.onCategoryChanged,
  });

  @override
  State<TvLiveScreen> createState() => _TvLiveScreenState();
}

class _TvLiveScreenState extends State<TvLiveScreen> {
  List<XtreamCategory> _categories = [];
  bool _loadingCategories = true;

  bool _showFavorites = false;
  XtreamCategory? _category;
  List<XtreamLiveStream> _channels = [];
  bool _loadingChannels = false;

  XtreamLiveStream? _previewChannel;
  PlayerBackend? _backend;
  bool _previewLoading = false;
  bool _previewFailed = false;
  List<XtreamEpgListing> _epg = [];
  Timer? _previewDebounce;
  int _previewRequestId = 0;
  StreamSubscription<String>? _previewErrorSub;

  /// Serializes every backend switch (dispose-old, open-new) end to end.
  /// Without this, a slow `open()` for channel A (a live network connect —
  /// routinely seconds, not instant) could still be in flight when the user
  /// moved on to channel B, and B's dispose would tear down A's native
  /// player *while A's own open() was still mid-flight on it* — two
  /// concurrent native lifecycle calls on the same instance. On a TV box's
  /// tightly limited hardware decoder slots that's exactly the kind of
  /// thing that leaves a decoder claimed by a zombie instance, which is a
  /// very plausible explanation for channels that hang forever on
  /// "Connecting..." and for playback instability once something does
  /// connect. Chaining onto this Future guarantees each switch's open()
  /// (success or failure) fully settles before the next one's dispose even
  /// starts, so two backends are never mid-lifecycle at once.
  Future<void> _backendChain = Future.value();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _disposeBackend();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final content = context.read<ContentProvider>();
    if (content.liveCategories.isEmpty) {
      await content.loadLiveCategories();
    }
    if (!mounted) return;
    setState(() {
      _categories = content.liveCategories;
      _loadingCategories = false;
    });
    if (_categories.isNotEmpty) {
      final remembered = widget.initialCategoryId;
      XtreamCategory? match;
      if (remembered != null) {
        for (final c in _categories) {
          if (c.categoryId == remembered) {
            match = c;
            break;
          }
        }
      }
      _selectCategory(match ?? _categories.first);
    }
  }

  Future<void> _selectCategory(XtreamCategory category) async {
    widget.onCategoryChanged?.call(category.categoryId);
    setState(() {
      _showFavorites = false;
      _category = category;
      _loadingChannels = true;
      _channels = [];
    });
    final content = context.read<ContentProvider>();
    List<XtreamLiveStream> channels;
    try {
      channels = await content.getLiveStreams(categoryId: category.categoryId);
    } catch (_) {
      channels = [];
    }
    if (!mounted ||
        _showFavorites ||
        _category?.categoryId != category.categoryId) {
      return;
    }
    setState(() {
      _channels = channels;
      _loadingChannels = false;
    });
    if (channels.isNotEmpty) _requestPreview(channels.first);
  }

  void _selectFavorites(List<XtreamLiveStream> favoriteChannels) {
    setState(() {
      _showFavorites = true;
      _category = null;
      _loadingChannels = false;
      _channels = favoriteChannels;
    });
    if (favoriteChannels.isNotEmpty) _requestPreview(favoriteChannels.first);
  }

  /// Focus moving down the channel list previews each channel, but a debounce
  /// keeps a quick scroll-through from opening (and immediately tearing down)
  /// a new stream on every single row it passes over.
  void _requestPreview(XtreamLiveStream channel) {
    if (_previewChannel?.streamId == channel.streamId) return;
    setState(() => _previewChannel = channel);
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 450), () {
      final requestId = ++_previewRequestId;
      // Queue onto the chain rather than starting immediately — see the
      // field doc comment on _backendChain for why.
      _backendChain = _backendChain.then(
        (_) => _startPreview(channel, requestId),
      );
    });
  }

  Future<void> _startPreview(XtreamLiveStream channel, int requestId) async {
    await _disposeBackend();
    // Either dismounted, or superseded by a later request while this one
    // was waiting its turn in the chain — either way, nothing to open.
    if (!mounted || requestId != _previewRequestId) return;

    setState(() {
      _previewLoading = true;
      _previewFailed = false;
      _epg = [];
    });

    final content = context.read<ContentProvider>();
    content.getShortEpg(channel.streamId).then((epg) {
      if (mounted && requestId == _previewRequestId) {
        setState(() => _epg = epg);
      }
    });

    PlayerBackend? backend;
    try {
      final url = channel.streamUrl(
        content.baseUrl,
        content.username,
        content.password,
      );
      backend = createPlayerBackend();
      if (requestId != _previewRequestId) {
        await backend.dispose();
        return;
      }
      // A stream that fails to connect is reported through errorStream,
      // not by open() throwing — ExoPlayerBackend swallows its own
      // initialization errors internally so a single bad channel doesn't
      // crash the whole open() call. Without listening here, `await
      // backend.open(...)` below returns normally either way, the spinner
      // clears, and the preview just silently shows nothing with no
      // indication anything went wrong — which is exactly the "keeps
      // loading then stops, with nothing playing" symptom this fixes.
      _previewErrorSub?.cancel();
      _previewErrorSub = backend.errorStream.listen((_) {
        if (mounted && requestId == _previewRequestId) {
          setState(() {
            _previewLoading = false;
            _previewFailed = true;
          });
        }
      });
      if (mounted) setState(() => _backend = backend);
      await backend.open(
        url: url,
        httpHeaders: const {'User-Agent': 'NX-IPTV/1.0'},
        autoPlay: true,
      );
      if (mounted && requestId == _previewRequestId && !_previewFailed) {
        setState(() => _previewLoading = false);
      }
    } catch (_) {
      try {
        await backend?.dispose();
      } catch (_) {}
      if (mounted && requestId == _previewRequestId) {
        setState(() {
          _previewLoading = false;
          _previewFailed = true;
          _backend = null;
        });
      }
    }
  }

  /// Re-runs the preview for whatever channel is currently showing (e.g.
  /// after [_previewFailed] — a transient hiccup shouldn't need reselecting
  /// the channel from the list to try again).
  void _retryPreview() {
    final channel = _previewChannel;
    if (channel == null) return;
    final requestId = ++_previewRequestId;
    _backendChain = _backendChain.then(
      (_) => _startPreview(channel, requestId),
    );
  }

  Future<void> _disposeBackend() async {
    await _previewErrorSub?.cancel();
    _previewErrorSub = null;
    final backend = _backend;
    if (mounted) {
      setState(() => _backend = null);
    } else {
      _backend = null;
    }
    try {
      await backend?.stop();
      await backend?.dispose();
    } catch (_) {}
  }

  void _openFullscreen(XtreamLiveStream channel) {
    final content = context.read<ContentProvider>();
    final initialIndex = _channels.indexWhere(
      (c) => c.streamId == channel.streamId,
    );
    final playlist = _channels
        .map(
          (c) => {
            'url': c.streamUrl(
              content.baseUrl,
              content.username,
              content.password,
            ),
            'title': c.name,
            'coverUrl': c.streamIcon,
            'isLive': true,
            'mediaId': c.streamId.toString(),
            'mediaType': MediaType.live,
            'rawMediaData': c.toJson(),
          },
        )
        .toList();

    _previewDebounce?.cancel();
    _disposeBackend();
    pushTv(
      context,
      PlayerScreen(
        streamUrl: channel.streamUrl(
          content.baseUrl,
          content.username,
          content.password,
        ),
        title: channel.name,
        coverUrl: channel.streamIcon,
        isLive: true,
        mediaId: channel.streamId.toString(),
        mediaType: MediaType.live,
        rawMediaData: channel.toJson(),
        playlist: playlist,
        initialIndex: initialIndex < 0 ? 0 : initialIndex,
      ),
    );
  }

  /// Movies/Series delegate straight to [widget.onSelectSection] — see its
  /// doc comment: TvHomeScreen's callback pops this screen and switches its
  /// own body, so nothing needs popping here first. Live re-selecting Live
  /// is a no-op, matching the old nav bar's identical guard. Search and
  /// Settings are self-contained pushes, same as they always were.
  void _selectSidebarItem(TvSidebarItem item) {
    switch (item) {
      case TvSidebarItem.movies:
        widget.onSelectSection(TvSection.movies);
      case TvSidebarItem.series:
        widget.onSelectSection(TvSection.series);
      case TvSidebarItem.live:
        break;
      case TvSidebarItem.search:
        // Search is *pushed*, not a replacement for this screen — this
        // widget (and its live preview player, still open and playing) stay
        // mounted underneath the whole time. Without stopping it first, the
        // channel that was previewing keeps playing — audibly, even though
        // nothing on screen shows it — for as long as Search stays open.
        // See the identical comment on the settings case below.
        _previewDebounce?.cancel();
        _disposeBackend();
        pushTv(
          context,
          TvSearchScreen(
            onSelectSection: (s) {
              Navigator.of(context).pop();
              widget.onSelectSection(s);
            },
          ),
        ).then((_) {
          if (mounted) _retryPreview();
        });
      case TvSidebarItem.settings:
        // Same reasoning as search above — this was the "settings plays the
        // first live channel's audio" report: it wasn't Settings starting
        // anything, it was Live's own preview left running underneath it.
        _previewDebounce?.cancel();
        _disposeBackend();
        pushTv(
          context,
          TvSettingsScreen(
            onSelectSection: (s) {
              Navigator.of(context).pop();
              widget.onSelectSection(s);
            },
          ),
        ).then((_) {
          if (mounted) _retryPreview();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final userPrefs = context.watch<UserPrefsProvider>();
    final isArabic = userPrefs.locale == 'ar';
    final liveFavorites = userPrefs.favorites
        .where((f) => f.type == MediaType.live)
        .toList();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _disposeBackend();
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
            child: Stack(
              children: [
                // Left inset matches TvSidebar's resting width exactly (see
                // TvHomeScreen's identical pattern) — this screen has no
                // MediaQuery-driven poster sizing to account for (the
                // category/channel columns are fixed-width, the preview
                // panel is a plain Expanded), so a left padding alone is
                // enough here.
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TvMetrics.sidebarCollapsedWidth,
                      20,
                      40,
                      20,
                    ),
                    child: _loadingCategories
                        ? Center(
                            child: CircularProgressIndicator(
                              color: colors.brandPrimary,
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 170,
                                child: _CategoryList(
                                  categories: _categories,
                                  selected: _category,
                                  showFavorites: _showFavorites,
                                  hasFavorites: liveFavorites.isNotEmpty,
                                  isArabic: isArabic,
                                  onSelectCategory: _selectCategory,
                                  onSelectFavorites: () => _selectFavorites(
                                    liveFavorites
                                        .map(
                                          (f) => XtreamLiveStream.fromJson(
                                            f.rawData,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(
                                width: 220,
                                child: _ChannelList(
                                  channels: _channels,
                                  loading: _loadingChannels,
                                  previewingId: _previewChannel?.streamId,
                                  isArabic: isArabic,
                                  onFocusChannel: _requestPreview,
                                  // On a D-pad, hovering a row already
                                  // previews it (onFocusChannel above) — so
                                  // Select going straight to fullscreen is
                                  // the fast path, not a shortcut past
                                  // anything. Touch has no hover: tapping is
                                  // the *only* signal a channel was chosen
                                  // at all, so on iPad a tap previews first,
                                  // same as landing on a row via D-pad would
                                  // — the dedicated fullscreen button in the
                                  // preview panel (see _PreviewPanel below)
                                  // is then the explicit "make it big" step.
                                  onSelectChannel: Platform.isIOS
                                      ? _requestPreview
                                      : _openFullscreen,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _PreviewPanel(
                                  channel: _previewChannel,
                                  backend: _backend,
                                  loading: _previewLoading,
                                  failed: _previewFailed,
                                  epg: _epg,
                                  isArabic: isArabic,
                                  onFullscreen: () {
                                    final channel = _previewChannel;
                                    if (channel != null) {
                                      _openFullscreen(channel);
                                    }
                                  },
                                  onRetry: _retryPreview,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  child: TvSidebar(
                    active: TvSection.live,
                    currentItem: TvSidebarItem.live,
                    isArabic: isArabic,
                    onSelect: _selectSidebarItem,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  final List<XtreamCategory> categories;
  final XtreamCategory? selected;
  final bool showFavorites;
  final bool hasFavorites;
  final bool isArabic;
  final ValueChanged<XtreamCategory> onSelectCategory;
  final VoidCallback onSelectFavorites;

  const _CategoryList({
    required this.categories,
    required this.selected,
    required this.showFavorites,
    required this.hasFavorites,
    required this.isArabic,
    required this.onSelectCategory,
    required this.onSelectFavorites,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (hasFavorites) ...[
          _CategoryRow(
            label: isArabic ? '♥ المفضلة' : '♥ Favorites',
            selected: showFavorites,
            onTap: onSelectFavorites,
          ),
          const SizedBox(height: 6),
        ],
        for (final category in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _CategoryRow(
              label: category.categoryName,
              selected:
                  !showFavorites && selected?.categoryId == category.categoryId,
              onTap: () => onSelectCategory(category),
            ),
          ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TvFocusScope(
      onTap: onTap,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: TvMetrics.focusAnim,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: selected
                ? LinearGradient(colors: colors.brandGradient)
                : null,
            color: selected
                ? null
                : (focused
                      ? colors.surface
                      : colors.surface.withValues(alpha: 0.35)),
            border: Border.all(
              color: focused ? colors.ink : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : colors.ink.withValues(alpha: 0.85),
            ),
          ),
        );
      },
    );
  }
}

class _ChannelList extends StatelessWidget {
  final List<XtreamLiveStream> channels;
  final bool loading;
  final int? previewingId;
  final bool isArabic;
  final ValueChanged<XtreamLiveStream> onFocusChannel;
  final ValueChanged<XtreamLiveStream> onSelectChannel;

  const _ChannelList({
    required this.channels,
    required this.loading,
    required this.previewingId,
    required this.isArabic,
    required this.onFocusChannel,
    required this.onSelectChannel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.brandPrimary),
      );
    }
    if (channels.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد قنوات' : 'No channels',
          style: AppType.sans(
            fontSize: 12,
            color: colors.ink.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _ChannelRow(
            index: index + 1,
            channel: channel,
            previewing: previewingId == channel.streamId,
            autofocus: index == 0,
            onFocus: () => onFocusChannel(channel),
            onSelect: () => onSelectChannel(channel),
          ),
        );
      },
    );
  }
}

class _ChannelRow extends StatefulWidget {
  final int index;
  final XtreamLiveStream channel;
  final bool previewing;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onSelect;

  const _ChannelRow({
    required this.index,
    required this.channel,
    required this.previewing,
    required this.autofocus,
    required this.onFocus,
    required this.onSelect,
  });

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  /// True while focus is on this row's channel tile *or* its favourite
  /// button — the button only exists while this is true, so it appears as
  /// you land on a channel and disappears when you move off it.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final userPrefs = context.watch<UserPrefsProvider>();
    final channel = widget.channel;
    final favoriteId = channel.streamId.toString();
    final isFav = userPrefs.isFavorite(favoriteId);
    final isArabic = userPrefs.locale == 'ar';

    // Observes focus for the whole row — the tile and the favourite button
    // are siblings inside it, so this is true for either. It is not
    // focusable itself and is skipped by traversal; it only decides
    // whether the favourite button is on screen.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus != _hovered) setState(() => _hovered = hasFocus);
      },
      child: Row(
        children: [
          Expanded(
            child: TvFocusScope(
              onTap: widget.onSelect,
              autofocus: widget.autofocus,
              onFocusChange: (focused) {
                if (focused) widget.onFocus();
              },
              builder: (context, focused) {
                final active = focused || widget.previewing;
                return AnimatedContainer(
                  duration: TvMetrics.focusAnim,
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: widget.previewing
                        ? colors.brandPrimary.withValues(alpha: 0.16)
                        : colors.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: focused
                          ? colors.ink
                          : (widget.previewing
                                ? colors.brandPrimary
                                : colors.border),
                      width: focused ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${widget.index}',
                        style: AppType.sans(
                          fontSize: 11,
                          color: colors.ink.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: channel.streamIcon.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: channel.streamIcon,
                                width: 34,
                                height: 34,
                                fit: BoxFit.contain,
                                errorWidget: (_, _, _) => Container(
                                  width: 34,
                                  height: 34,
                                  color: colors.surfaceMuted,
                                  child: Icon(
                                    Icons.tv_rounded,
                                    size: 16,
                                    color: colors.ink.withValues(alpha: 0.24),
                                  ),
                                ),
                              )
                            : Container(
                                width: 34,
                                height: 34,
                                color: colors.surfaceMuted,
                                child: Icon(
                                  Icons.tv_rounded,
                                  size: 16,
                                  color: colors.ink.withValues(alpha: 0.24),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active
                                ? colors.ink
                                : colors.ink.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      // Shown only for channels already favourited, so you
                      // can see at a glance which ones are while scrolling.
                      // Purely decorative — the toggle is the sibling
                      // button, which is a separate focus node precisely so
                      // it can actually be reached: one nested inside this
                      // tile's own focus node never could be.
                      if (isFav) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: colors.brandPrimary,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          // Appears only while this row has focus, and sits beside the
          // tile rather than inside it — press right off the channel to
          // reach it, select to toggle. Selecting the channel itself still
          // plays it, untouched.
          if (_hovered) ...[
            const SizedBox(width: 6),
            TvFocusScope(
              onTap: () => userPrefs.toggleFavorite(
                id: favoriteId,
                title: channel.name,
                posterUrl: channel.streamIcon,
                type: MediaType.live,
                rawData: channel.toJson(),
              ),
              builder: (context, favFocused) => AnimatedContainer(
                duration: TvMetrics.focusAnim,
                width: 40,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: favFocused
                      ? colors.brandPrimary
                      : colors.surface.withValues(alpha: 0.5),
                  border: Border.all(
                    color: favFocused ? colors.ink : colors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                  semanticLabel: isArabic ? 'المفضلة' : 'Favourite',
                  color: isFav && !favFocused
                      ? colors.brandPrimary
                      : colors.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final XtreamLiveStream? channel;
  final PlayerBackend? backend;
  final bool loading;
  final bool failed;
  final List<XtreamEpgListing> epg;
  final bool isArabic;
  final VoidCallback onFullscreen;
  final VoidCallback onRetry;

  const _PreviewPanel({
    required this.channel,
    required this.backend,
    required this.loading,
    required this.failed,
    required this.epg,
    required this.isArabic,
    required this.onFullscreen,
    required this.onRetry,
  });

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = channel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (backend != null)
                    backend!.buildVideoWidget(aspectRatio: 16 / 9)
                  else if (current == null)
                    Center(
                      child: Text(
                        isArabic
                            ? 'اختر قناة للمعاينة'
                            : 'Select a channel to preview',
                        style: AppType.sans(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (current != null)
                    Positioned(
                      top: 10,
                      left: 12,
                      right: 12,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              current.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.sans(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                shadows: const [
                                  Shadow(blurRadius: 6, color: Colors.black),
                                ],
                              ),
                            ),
                          ),
                          if (current.streamIcon.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: CachedNetworkImage(
                                imageUrl: current.streamIcon,
                                width: 26,
                                height: 26,
                                errorWidget: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          // The explicit "make it big" step — see the
                          // onSelectChannel wiring above for why this
                          // exists as its own control rather than a tap on
                          // the channel already doing this: on iPad,
                          // tapping a channel only previews it, exactly
                          // like landing on it via D-pad would.
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: TvFocusScope(
                              onTap: onFullscreen,
                              builder: (context, focused) => Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: focused
                                      ? colors.brandPrimary
                                      : Colors.black.withValues(alpha: 0.45),
                                ),
                                child: const Icon(
                                  Icons.fullscreen_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (loading)
                    Center(
                      child: CircularProgressIndicator(
                        color: colors.brandPrimary,
                        strokeWidth: 2.5,
                      ),
                    ),
                  if (failed && !loading && current != null)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.white54,
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isArabic
                                ? 'تعذر تحميل المعاينة'
                                : "Couldn't load preview",
                            style: AppType.sans(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TvFocusScope(
                            onTap: onRetry,
                            builder: (context, focused) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: focused
                                    ? colors.brandPrimary
                                    : Colors.white.withValues(alpha: 0.08),
                                border: Border.all(
                                  color: focused
                                      ? Colors.transparent
                                      : Colors.white24,
                                ),
                              ),
                              child: Text(
                                isArabic ? 'إعادة المحاولة' : 'Retry',
                                style: AppType.sans(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
        if (epg.isNotEmpty) ...[
          const SizedBox(height: 12),
          _EpgCard(
            listing: epg.first,
            isArabic: isArabic,
            formatTime: _formatTime,
          ),
        ],
      ],
    );
  }
}

class _EpgCard extends StatelessWidget {
  final XtreamEpgListing listing;
  final bool isArabic;
  final String Function(DateTime) formatTime;

  const _EpgCard({
    required this.listing,
    required this.isArabic,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (listing.title.isEmpty) return const SizedBox.shrink();
    final progress = listing.progress;
    final start = listing.start;
    final end = listing.end;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.ink,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  listing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
              ),
            ],
          ),
          if (listing.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              listing.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.sans(
                fontSize: 11.5,
                height: 1.35,
                color: colors.ink.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (progress != null && start != null && end != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: colors.surfaceMuted,
                valueColor: AlwaysStoppedAnimation<Color>(colors.ink),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatTime(start)} - ${formatTime(end)}',
              style: AppType.sans(
                fontSize: 10.5,
                color: colors.ink.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
