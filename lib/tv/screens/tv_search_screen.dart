import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/user_prefs_provider.dart'
    show MediaType, UserPrefsProvider;
import '../../screens/player_screen.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_search_field.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import '../widgets/tv_content_row.dart';
import '../widgets/tv_nav_bar.dart' show TvSection;
import '../widgets/tv_poster_card.dart';
import '../widgets/tv_sidebar.dart';
import 'tv_movie_detail_screen.dart';
import 'tv_series_detail_screen.dart';

enum _ResultKind { movie, series, live }

/// One search hit, uniformly wrapping whichever of the three content types
/// it actually is so the results grid/tap-handling doesn't need to branch
/// on type at every call site.
class _SearchResult {
  final _ResultKind kind;
  final String title;
  final String poster;
  final dynamic item;

  _SearchResult.movie(XtreamVodStream m)
    : kind = _ResultKind.movie,
      title = m.name,
      poster = m.streamIcon,
      item = m;

  _SearchResult.series(XtreamSeries s)
    : kind = _ResultKind.series,
      title = s.name,
      poster = s.cover,
      item = s;

  _SearchResult.live(XtreamLiveStream l)
    : kind = _ResultKind.live,
      title = l.name,
      poster = l.streamIcon,
      item = l;
}

/// Search across the whole library — movies, series, *and* live channels
/// together, not scoped to whatever section the user happened to open it
/// from. Reached from every screen's sidebar (see TvSidebar), so it carries
/// the same persistent sidebar itself, matching Home/Live/Settings.
///
/// Deliberately no `PopScope` here: Back should just pop this pushed route
/// straight back to whichever screen opened it, exactly Flutter's default
/// behavior — the same policy TvLiveScreen and the player use via their own
/// explicit `PopScope(canPop: true, ...)`. Leave this screen without one;
/// adding one "for consistency" would be the actual inconsistency, since
/// the only screen that should ever intercept Back is the true root
/// (TvHomeScreen, for exit-confirmation).
class TvSearchScreen extends StatefulWidget {
  final ValueChanged<TvSection> onSelectSection;

  const TvSearchScreen({super.key, required this.onSelectSection});

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Shares ContentProvider's one "whole catalog" cache (see
    // loadAllContent/searchAll) instead of this screen doing its own
    // separate Future.wait([getVodStreams(), getSeriesList(),
    // getLiveStreams()]) fetch of the exact same data — that duplicate
    // fetch is what home_screen.dart's phone search already avoided, and
    // firing it independently here meant two full-catalog fetches could
    // race in flight together (e.g. this screen opening while Home's own
    // "New" row was still loading). Xtream panels commonly cap concurrent
    // connections; stacking redundant full-catalog requests on top of
    // whatever else the app was already loading is exactly what a small/
    // budget panel's connection limit turns into an intermittent
    // "temporarily returns an HTML block page instead of JSON" failure —
    // the loadAllContent()/isLoadingAllContent guard below means at most
    // one such fetch is ever in flight for the whole app.
    final content = context.read<ContentProvider>();
    if (!content.isAllContentLoaded && !content.isLoadingAllContent) {
      content.loadAllContent();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_SearchResult> get _movieResults {
    if (_query.trim().isEmpty) return const [];
    final results = context.read<ContentProvider>().searchAll(_query);
    return [for (final m in results.movies) _SearchResult.movie(m)];
  }

  List<_SearchResult> get _seriesResults {
    if (_query.trim().isEmpty) return const [];
    final results = context.read<ContentProvider>().searchAll(_query);
    return [for (final s in results.series) _SearchResult.series(s)];
  }

  List<_SearchResult> get _liveResults {
    if (_query.trim().isEmpty) return const [];
    final results = context.read<ContentProvider>().searchAll(_query);
    return [for (final l in results.liveStreams) _SearchResult.live(l)];
  }

  void _open(_SearchResult result) {
    switch (result.kind) {
      case _ResultKind.movie:
        pushTv(
          context,
          TvMovieDetailScreen(movie: result.item as XtreamVodStream),
        );
      case _ResultKind.series:
        pushTv(
          context,
          TvSeriesDetailScreen(series: result.item as XtreamSeries),
        );
      case _ResultKind.live:
        _openLive(result.item as XtreamLiveStream);
    }
  }

  void _openLive(XtreamLiveStream channel) {
    final content = context.read<ContentProvider>();
    final url = channel.streamUrl(
      content.baseUrl,
      content.username,
      content.password,
    );
    pushTv(
      context,
      PlayerScreen(
        streamUrl: url,
        title: channel.name,
        coverUrl: channel.streamIcon,
        isLive: true,
        mediaId: channel.streamId.toString(),
        mediaType: MediaType.live,
        rawMediaData: channel.toJson(),
        playlist: [
          {
            'url': url,
            'title': channel.name,
            'coverUrl': channel.streamIcon,
            'isLive': true,
            'mediaId': channel.streamId.toString(),
            'mediaType': MediaType.live,
            'rawMediaData': channel.toJson(),
          },
        ],
        initialIndex: 0,
      ),
    );
  }

  void _selectSidebarItem(TvSidebarItem item) {
    switch (item) {
      case TvSidebarItem.movies:
        // widget.onSelectSection already pops whatever it needs to on its
        // own (see how each caller — Home/Live/Settings — builds it) — an
        // extra pop() here on top of that would remove one route too many.
        widget.onSelectSection(TvSection.movies);
      case TvSidebarItem.series:
        widget.onSelectSection(TvSection.series);
      case TvSidebarItem.live:
        widget.onSelectSection(TvSection.live);
      case TvSidebarItem.settings:
        // Settings itself owns the "open settings" push — search doesn't
        // know how to build one directly, so this just backs out to
        // whichever screen opened search, matching how re-selecting the
        // section already active anywhere else in the app is a no-op/back.
        Navigator.of(context).pop();
      case TvSidebarItem.search:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';
    // Watched (not read) so this screen rebuilds once the shared
    // loadAllContent() fetch triggered in initState finishes — whichever
    // screen actually triggers it first, every screen sharing this cache
    // rebuilds together when it resolves.
    context.watch<ContentProvider>();

    return Scaffold(
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Same fix as TvHomeScreen's identical Stack: TvContentRow's
              // posters self-size from MediaQuery's screen width (see
              // TvMetrics.posterWidth), which knows nothing about the
              // sidebar's left inset below — without this override they'd
              // compute themselves too wide for the space actually left
              // over once the sidebar is accounted for.
              const extraLeftInset = TvMetrics.sidebarCollapsedWidth - 40;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(left: extraLeftInset),
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: Size(
                            constraints.maxWidth - extraLeftInset,
                            constraints.maxHeight,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(40, 16, 40, 16),
                          child: _buildContent(colors, isArabic),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    child: TvSidebar(
                      active: null,
                      currentItem: TvSidebarItem.search,
                      isArabic: isArabic,
                      onSelect: _selectSidebarItem,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppColors colors, bool isArabic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TvSearchField(
          controller: _searchController,
          autofocus: true,
          hint: isArabic
              ? 'ابحث في الأفلام والمسلسلات والبث المباشر'
              : 'Search movies, series, and live TV',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 16),
        Expanded(child: _buildResults(colors, isArabic)),
      ],
    );
  }

  Widget _buildResults(AppColors colors, bool isArabic) {
    final content = context.watch<ContentProvider>();
    if (content.isLoadingAllContent) {
      return Center(
        child: CircularProgressIndicator(color: colors.brandPrimary),
      );
    }
    if (content.allContentError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              content.allContentError!,
              textAlign: TextAlign.center,
              style: AppType.sans(
                color: colors.ink.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            TvFocusable(
              onTap: () => content.loadAllContent(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.brandPrimary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isArabic ? 'إعادة المحاولة' : 'Retry',
                  style: AppType.sans(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_query.trim().isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'ابدأ الكتابة للبحث' : 'Start typing to search',
          style: AppType.sans(
            color: colors.ink.withValues(alpha: 0.4),
            fontSize: 14,
          ),
        ),
      );
    }
    final movies = _movieResults;
    final series = _seriesResults;
    final live = _liveResults;
    if (movies.isEmpty && series.isEmpty && live.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد نتائج' : 'No results',
          style: AppType.sans(
            color: colors.ink.withValues(alpha: 0.4),
            fontSize: 14,
          ),
        ),
      );
    }
    // Grouped under their own section — Movies, Series, Live — the same
    // titled-row shape every other content list in the app already uses
    // (TvContentRow), rather than one flat mixed grid, so results read the
    // same way the rest of the app does and stay obviously sorted by type
    // at a glance.
    var autofocused = false;
    Widget? section(String title, List<_SearchResult> items) {
      if (items.isEmpty) return null;
      final children = [
        for (final result in items)
          TvPosterCard(
            title: result.title,
            posterUrl: result.poster,
            autofocus: !autofocused && (autofocused = true),
            placeholderIcon: switch (result.kind) {
              _ResultKind.movie => Icons.movie_rounded,
              _ResultKind.series => Icons.video_library_rounded,
              _ResultKind.live => Icons.live_tv_rounded,
            },
            onTap: () => _open(result),
          ),
      ];
      return Padding(
        padding: const EdgeInsets.only(bottom: TvMetrics.rowGap),
        child: TvContentRow(
          title: title,
          isArabic: isArabic,
          children: children,
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ?section(isArabic ? 'أفلام' : 'Movies', movies),
        ?section(isArabic ? 'مسلسلات' : 'Series', series),
        ?section(isArabic ? 'مباشر' : 'Live', live),
      ],
    );
  }
}
