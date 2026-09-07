import 'package:flutter/material.dart';
// For ScrollCacheExtent — not re-exported by material.dart.
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:provider/provider.dart';

import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/user_prefs_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../widgets/category_card.dart' show CategoryType;
import '../../widgets/tv_focusable.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import '../widgets/tv_content_row.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_nav_bar.dart' show TvSection;
import '../widgets/tv_poster_card.dart';
import '../widgets/tv_sidebar.dart';
import 'tv_live_screen.dart';
import 'tv_media_grid_screen.dart';
import 'tv_movie_detail_screen.dart';
import 'tv_search_screen.dart';
import 'tv_series_detail_screen.dart';
import 'tv_settings_screen.dart';

/// The TV home: a persistent top nav over a single scrolling page of
/// horizontal content rows.
///
/// Replaces the previous hub-of-tiles screen. The hub cost a full round trip
/// (back out, pick a section, drill in) to reach anything, and showed no
/// actual content until two screens deep — this puts real artwork on screen
/// immediately and keeps every section one D-pad "up" away.
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  TvSection _section = TvSection.movies;

  // ─── Focus-position memory ──────────────────────────────────────────────
  //
  // Two complementary mechanisms, for the two ways focus can leave content
  // and come back (see the TV focus rebuild plan):
  //
  // 1. Same section, no rebuild at all (Left to the sidebar to glance at it,
  //    Right back to content with nothing in between) — the poster that was
  //    focused before is still a real, un-disposed FocusNode the whole time,
  //    so simply keeping a reference to it and re-requesting focus on
  //    Right is exact and costs nothing extra. _lastContentFocus is that
  //    reference, refreshed by the observer Focus wrapping _buildBody's
  //    result in build() below.
  // 2. An actual section switch (Movies -> Series -> Movies) — every row in
  //    the old section gets disposed (see _LazyCategoryRow's key, which
  //    includes _section.name), so nothing survives to re-focus directly.
  //    _lastFocusedRowKey remembers which row (by category id, or the
  //    continue-watching sentinel below) was last focused *per section*,
  //    and the itemBuilder in _buildBody uses it to steer the existing
  //    autofocus/autofocusFirst flags onto that same row instead of always
  //    row 0 — reusing Flutter's own autofocus mechanism (which already
  //    correctly waits for a lazily-loading row's content to arrive) rather
  //    than manually chasing a FocusNode through an async row load.
  FocusNode? _lastContentFocus;
  final Map<TvSection, String> _lastFocusedRowKey = {};
  static const String _kContinueWatchingKey = '__continue_watching__';

  /// Live is always a fresh push (see TvLiveScreen's own doc comment on
  /// initialCategoryId) — this is the only ancestor that survives its
  /// push/pop cycle, so it's the only place this can live.
  String? _lastLiveCategoryId;

  void _handleContentFocusChange(bool hasFocus) {
    if (hasFocus) _lastContentFocus = FocusManager.instance.primaryFocus;
  }

  void _handleSidebarExitRight() {
    final node = _lastContentFocus;
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
    }
    // No stashed node (e.g. very first frame, nothing focused yet) — do
    // nothing and let whatever already has default-traversal focus stay,
    // rather than forcing a guess.
  }

  /// Drives the row list so focus moving up into the nav bar can bring the
  /// list back to the top with it. The nav bar is a sibling of the list,
  /// not a child, so nothing otherwise scrolls the list when focus leaves
  /// it — scrolling down a few rows and then going back up landed on the
  /// nav bar with the list still parked where it was, hiding Continue
  /// Watching (and the first category) above the viewport with no way to
  /// bring them back short of scrolling down and up again.
  final ScrollController _bodyScroll = ScrollController();

  @override
  void dispose() {
    _bodyScroll.dispose();
    super.dispose();
  }

  void _scrollBodyToTop() {
    if (!_bodyScroll.hasClients || _bodyScroll.offset <= 0) return;
    _bodyScroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  bool get _isMovies => _section == TvSection.movies;
  CategoryType get _type =>
      _isMovies ? CategoryType.movie : CategoryType.series;

  void _selectSection(TvSection section) {
    if (section == TvSection.live) {
      // Live is its own full-screen browser (categories + channels + a
      // live preview together), not another row-based section body, so it
      // stays a pushed route rather than an inline tab like Movies/Series.
      // Delegates back to _selectSection itself (not a raw setState) so a
      // Live pick made from somewhere nested under Live (Settings opened
      // from within Live, say) still gets Live's own real pushed route
      // rather than just flipping a flag nothing here renders differently
      // for.
      pushTv(
        context,
        TvLiveScreen(
          initialCategoryId: _lastLiveCategoryId,
          onCategoryChanged: (id) => _lastLiveCategoryId = id,
          onSelectSection: (s) {
            Navigator.of(context).pop();
            _selectSection(s);
          },
        ),
      );
      return;
    }
    // Re-selecting the section already showing used to still unconditionally
    // unfocus below — since _LazyCategoryRow is keyed by
    // '${_section.name}-${category.categoryId}', an unchanged _section
    // means the same key, so Flutter reuses the existing (already-attached,
    // no-longer-eligible-for-autofocus) Element instead of remounting it.
    // Nothing then re-claimed focus: a real dead end. Guarding on an actual
    // change fixes that at the source, and TvSidebar's own onExitRight (see
    // _handleSidebarExitRight above) is what correctly handles "came from
    // the sidebar without changing section" instead.
    if (section == _section) return;
    // Movies/Series is an in-place rebuild, not a route push — so unlike
    // Live/Settings/Search (each their own route, and so their own fresh
    // FocusScope), whatever already had D-pad focus here (almost always
    // the sidebar item that was just tapped) keeps it right through the
    // rebuild: autofocus on the new first poster only takes effect when
    // nothing else already holds focus, so without clearing it first the
    // sidebar just stayed focused (and so stayed visibly expanded) with
    // the content switched invisibly underneath.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _section = section);
  }

  void _selectSidebarItem(TvSidebarItem item) {
    switch (item) {
      case TvSidebarItem.movies:
        _selectSection(TvSection.movies);
      case TvSidebarItem.series:
        _selectSection(TvSection.series);
      case TvSidebarItem.live:
        _selectSection(TvSection.live);
      case TvSidebarItem.search:
        pushTv(
          context,
          TvSearchScreen(
            onSelectSection: (s) {
              Navigator.of(context).pop();
              _selectSection(s);
            },
          ),
        );
      case TvSidebarItem.settings:
        pushTv(
          context,
          TvSettingsScreen(
            // Reuses _selectSection so a Live pick from within Settings
            // still gets Live's own pushed route, not just a silent
            // section-flag change nothing renders differently for.
            onSelectSection: (s) {
              Navigator.of(context).pop();
              _selectSection(s);
            },
          ),
        );
    }
  }

  void _openMovie(XtreamVodStream movie) =>
      pushTv(context, TvMovieDetailScreen(movie: movie));

  void _openSeries(XtreamSeries series) =>
      pushTv(context, TvSeriesDetailScreen(series: series));

  void _openCategory(XtreamCategory category) =>
      pushTv(context, TvMediaGridScreen(type: _type, category: category));

  void _openList(String title, List<dynamic> items) => pushTv(
    context,
    TvMediaGridScreen(type: _type, title: title, items: items),
  );

  /// Back on the home screen used to drop straight out of the app, which
  /// is easy to trigger by accident on a remote — one press too many while
  /// backing out of a detail screen and the whole app is gone. This asks
  /// first instead.
  Future<void> _confirmExit(bool isArabic) async {
    final colors = context.colors;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'الخروج من التطبيق؟' : 'Exit the app?',
                  style: AppType.title(colors.ink),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TvFocusScope(
                      onTap: () => Navigator.of(ctx).pop(false),
                      builder: (context, focused) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: focused
                              ? colors.surfaceElevated
                              : Colors.transparent,
                          border: Border.all(
                            color: focused ? colors.ink : colors.border,
                          ),
                        ),
                        child: Text(
                          isArabic ? 'رجوع' : 'Back',
                          style: AppType.bodySmall(colors.ink),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TvFocusScope(
                      // Focused by default so back-then-OK exits in two
                      // presses, while a stray single back still cannot.
                      autofocus: true,
                      onTap: () => Navigator.of(ctx).pop(true),
                      builder: (context, focused) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: focused
                              ? LinearGradient(colors: colors.brandGradient)
                              : null,
                          color: focused ? null : colors.surfaceElevated,
                          border: Border.all(
                            color: focused ? Colors.transparent : colors.border,
                          ),
                        ),
                        child: Text(
                          isArabic ? 'خروج' : 'Exit',
                          style: AppType.bodySmall(Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (shouldExit == true) await SystemNavigator.pop();
  }

  void _openHistory(bool isArabic) {
    final history = context.read<UserPrefsProvider>().history;
    _openList(isArabic ? 'السجل' : 'History', history);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = context.watch<ContentProvider>();
    final userPrefs = context.watch<UserPrefsProvider>();
    final isArabic = userPrefs.locale == 'ar';

    final categories = _isMovies
        ? content.vodCategories
        : content.seriesCategories;

    // Continue Watching is scoped to the section you're in, so the Movies
    // tab doesn't surface half-watched episodes and vice versa.
    final targetType = _isMovies ? MediaType.movie : MediaType.series;
    final continueItems = userPrefs.history
        .where((h) => h.type == targetType)
        .toList();

    return PopScope(
      // Never pops on its own — _confirmExit decides, and only it can
      // actually leave the app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit(isArabic);
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The sidebar is a pure overlay (see TvSidebar's doc
                // comment) — it never resizes this Stack, it just draws
                // over the left edge of it. What DOES need to shift is the
                // content underneath: it gets a fixed left inset equal to
                // the sidebar's resting (collapsed) width, applied here via
                // an outer Padding plus a matching MediaQuery override so
                // every poster row's self-computed width (see
                // TvMetrics.posterWidth, read from MediaQuery.sizeOf deep
                // inside TvPosterCard/TvContentRow) accounts for the
                // narrower space too — without this override those rows
                // would size themselves for the full screen width and
                // overflow past the actual available area.
                // 40 here is TvMetrics.safeArea's horizontal inset (one
                // side) — every row already reserves that much on its own
                // via its own Padding, so only the difference needs adding.
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
                          child: Focus(
                            // Observer only — see _lastContentFocus's doc
                            // comment. Wraps the whole body (not just the
                            // ListView) so the error-state Retry button
                            // counts as "content focus" too, not just
                            // posters.
                            canRequestFocus: false,
                            skipTraversal: true,
                            onFocusChange: _handleContentFocusChange,
                            child: _buildBody(
                              colors: colors,
                              isArabic: isArabic,
                              content: content,
                              categories: categories,
                              continueItems: continueItems,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      child: TvSidebar(
                        active: _section,
                        currentItem: _isMovies
                            ? TvSidebarItem.movies
                            : TvSidebarItem.series,
                        isArabic: isArabic,
                        onFocusEnter: _scrollBodyToTop,
                        onExitRight: _handleSidebarExitRight,
                        onSelect: _selectSidebarItem,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required AppColors colors,
    required bool isArabic,
    required ContentProvider content,
    required List<XtreamCategory> categories,
    required List<HistoryItem> continueItems,
  }) {
    final isLoading = _isMovies
        ? content.isLoadingVod
        : content.isLoadingSeries;

    if (categories.isEmpty && isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colors.brandPrimary),
      );
    }

    // A failed loadVodCategories()/loadSeriesCategories() call (the panel
    // occasionally returning an HTML block/rate-limit page instead of
    // JSON under load — see ContentProvider/xtream_api_service.dart) used
    // to leave `categories` empty with nothing checking *why* — the row
    // list below just rendered with zero items and no way back, reading
    // exactly like "the movies/series categories vanished" with no
    // explanation and no retry short of restarting the app. This is that
    // missing check.
    final error = _isMovies ? content.vodError : content.seriesError;
    if (categories.isEmpty && !isLoading && error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              textAlign: TextAlign.center,
              style: AppType.body(colors.ink.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 16),
            TvFocusable(
              autofocus: true,
              onTap: () => _isMovies
                  ? content.loadVodCategories()
                  : content.loadSeriesCategories(),
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
                  style: AppType.cardTitle(Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Everything above the category rows is a fixed number of slivers; the
    // rows themselves are built lazily so that opening this screen doesn't
    // fire one network request per category all at once. Each row fetches
    // its own content only once it's actually built (see _LazyCategoryRow),
    // which a builder defers until it scrolls near the viewport.
    final headerCount = continueItems.isEmpty ? 0 : 1;

    return ListView.builder(
      controller: _bodyScroll,
      // Keep a screen's worth of rows alive past the fold so D-pad focus
      // always has a built widget to move onto.
      scrollCacheExtent: const ScrollCacheExtent.pixels(900),
      padding: const EdgeInsets.only(top: 12, bottom: 40),
      itemCount: headerCount + categories.length,
      itemBuilder: (context, index) {
        var cursor = index;

        if (continueItems.isNotEmpty) {
          if (cursor == 0) {
            return Focus(
              // Observer only — see _lastFocusedRowKey's doc comment on
              // _lastContentFocus above. Cheap: fires only on this row's
              // own false->true transition, doesn't touch the per-item
              // FocusNodes below it at all.
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (hasFocus) {
                if (hasFocus) {
                  _lastFocusedRowKey[_section] = _kContinueWatchingKey;
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, TvMetrics.rowGap),
                child: TvContentRow(
                  title: isArabic ? 'متابعة المشاهدة' : 'Continue Watching',
                  isArabic: isArabic,
                  onSeeAll: () => _openHistory(isArabic),
                  children: [
                    for (final (i, item) in continueItems.indexed)
                      TvPosterCard(
                        title: item.title,
                        posterUrl: item.posterUrl,
                        subtitle: isArabic ? 'متابعة' : 'Continue',
                        progress: item.durationMilliseconds > 0
                            ? item.positionMilliseconds /
                                  item.durationMilliseconds
                            : null,
                        placeholderIcon: _isMovies
                            ? Icons.movie_rounded
                            : Icons.video_library_rounded,
                        // Lands D-pad focus somewhere real the instant this
                        // screen opens, or restores it here specifically if
                        // this was the row the user left from last (see
                        // _shouldAutofocusRow) — without either, the first
                        // press of any direction had no defined starting
                        // point to move from.
                        autofocus:
                            i == 0 &&
                            _shouldAutofocusRow(
                              _kContinueWatchingKey,
                              naturalDefault: true,
                            ),
                        onTap: () => _openHistoryItem(item),
                      ),
                  ],
                ),
              ),
            );
          }
          cursor -= 1;
        }

        final category = categories[cursor];
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (hasFocus) {
            if (hasFocus) _lastFocusedRowKey[_section] = category.categoryId;
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, TvMetrics.rowGap),
            child: _LazyCategoryRow(
              key: ValueKey('${_section.name}-${category.categoryId}'),
              category: category,
              isMovies: _isMovies,
              isArabic: isArabic,
              // Restores to this row specifically if it's the one the user
              // left from last (a real section switch, e.g. Movies ->
              // Series -> Movies); otherwise the original default — the
              // first row, only when Continue Watching isn't already
              // claiming the very first focusable card on screen.
              autofocusFirst: _shouldAutofocusRow(
                category.categoryId,
                naturalDefault: continueItems.isEmpty && cursor == 0,
              ),
              onSeeAll: () => _openCategory(category),
              onOpenMovie: _openMovie,
              onOpenSeries: _openSeries,
            ),
          ),
        );
      },
    );
  }

  /// Whether [rowKey] (a category id, or [_kContinueWatchingKey]) should get
  /// initial focus for the *current* [_section] — the row remembered as
  /// last-focused there, if this section has been visited before, otherwise
  /// [naturalDefault] (the plain "first row" answer, unchanged from before
  /// this feature existed).
  bool _shouldAutofocusRow(String rowKey, {required bool naturalDefault}) {
    final remembered = _lastFocusedRowKey[_section];
    if (remembered == null) return naturalDefault;
    return remembered == rowKey;
  }

  void _openHistoryItem(HistoryItem item) {
    if (item.type == MediaType.movie) {
      _openMovie(XtreamVodStream.fromJson(item.rawData));
    } else if (item.type == MediaType.series) {
      _openSeries(
        XtreamSeries(
          seriesId: item.rawData['series_id'] ?? int.tryParse(item.id) ?? 0,
          name: item.rawData['series_name'] ?? item.title,
          cover: item.rawData['series_cover'] ?? item.posterUrl,
          categoryId: item.rawData['category_id']?.toString() ?? '',
          plot: '',
          cast: '',
          director: '',
          genre: '',
          releaseDate: '',
          rating: '',
          lastModified:
              int.tryParse(item.rawData['last_modified']?.toString() ?? '0') ??
              0,
        ),
      );
    }
  }
}

/// One category's row, which fetches its own contents the first time it's
/// built.
///
/// Categories are fetched per row rather than up front because a provider
/// can carry dozens of them, and loading every one on entry would fire
/// dozens of parallel requests for content most of which is below the fold.
class _LazyCategoryRow extends StatefulWidget {
  final XtreamCategory category;
  final bool isMovies;
  final bool isArabic;
  final bool autofocusFirst;
  final VoidCallback onSeeAll;
  final void Function(XtreamVodStream) onOpenMovie;
  final void Function(XtreamSeries) onOpenSeries;

  const _LazyCategoryRow({
    super.key,
    required this.category,
    required this.isMovies,
    required this.isArabic,
    this.autofocusFirst = false,
    required this.onSeeAll,
    required this.onOpenMovie,
    required this.onOpenSeries,
  });

  @override
  State<_LazyCategoryRow> createState() => _LazyCategoryRowState();
}

class _LazyCategoryRowState extends State<_LazyCategoryRow> {
  List<dynamic> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = context.read<ContentProvider>();
      final result = widget.isMovies
          ? await content.getVodStreams(categoryId: widget.category.categoryId)
          : await content.getSeriesList(categoryId: widget.category.categoryId);
      if (!mounted) return;
      setState(() {
        // Only the head of the category is drawn — "See all" opens the full
        // grid, so pulling every item into a row nothing can scroll to the
        // end of would just cost memory.
        _items = result.take(20).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (_loading) {
      return _RowSkeleton(title: widget.category.categoryName, colors: colors);
    }
    // A category that resolved to nothing is dropped rather than shown as an
    // empty row — several providers ship categories that are permanently
    // empty, and a page of blank headers reads as a broken screen.
    if (_items.isEmpty) return const SizedBox.shrink();

    return TvContentRow(
      title: widget.category.categoryName,
      isArabic: widget.isArabic,
      onSeeAll: widget.onSeeAll,
      children: [
        for (final (i, item) in _items.indexed)
          TvPosterCard(
            title: _titleOf(item),
            posterUrl: _posterOf(item),
            placeholderIcon: widget.isMovies
                ? Icons.movie_rounded
                : Icons.video_library_rounded,
            autofocus: widget.autofocusFirst && i == 0,
            onTap: () {
              if (item is XtreamVodStream) {
                widget.onOpenMovie(item);
              } else if (item is XtreamSeries) {
                widget.onOpenSeries(item);
              }
            },
          ),
      ],
    );
  }

  String _titleOf(dynamic item) {
    if (item is XtreamVodStream) return item.name;
    if (item is XtreamSeries) return item.name;
    return '';
  }

  String _posterOf(dynamic item) {
    if (item is XtreamVodStream) return item.streamIcon;
    if (item is XtreamSeries) return item.cover;
    return '';
  }
}

/// Placeholder shown while a row's category is still loading, sized to match
/// the real row so the page doesn't jump as rows resolve.
class _RowSkeleton extends StatelessWidget {
  final String title;
  final AppColors colors;

  const _RowSkeleton({required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    final posterWidth = TvMetrics.posterWidth(MediaQuery.sizeOf(context).width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: colors.ink.withValues(alpha: 0.35),
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: posterWidth / TvMetrics.posterAspect,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: TvMetrics.postersPerRow,
            separatorBuilder: (_, _) =>
                const SizedBox(width: TvMetrics.posterGap),
            itemBuilder: (_, _) => Container(
              width: posterWidth,
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(TvMetrics.posterRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
