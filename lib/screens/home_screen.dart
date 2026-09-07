import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/content_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../models/xtream_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import 'series_screen.dart';
import 'movies_screen.dart';
import 'movie_details_screen.dart';
import 'series_details_screen.dart';
import 'player_screen.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';
import '../widgets/tv_focusable.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus) {
      final content = context.read<ContentProvider>();
      if (!content.isAllContentLoaded && !content.isLoadingAllContent) {
        content.loadAllContent();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = context.watch<ContentProvider>();
    final userPrefs = context.watch<UserPrefsProvider>();
    final colors = context.colors;

    return Scaffold(
      backgroundColor:
          Colors.transparent, // Background handled by MainNavigation
      // top: false — the hero runs under the status bar, which is what makes
      // it read as full-bleed rather than as a large card. Everything below
      // it is inset by the hero's own bottom padding.
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(
            bottom: 100,
          ), // Spacing for floating navbar
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_searchQuery.isEmpty) _buildHero(content, userPrefs),

              // No wordmark. The app's name belongs on the launcher icon and
              // the login screen, not above the content of every session —
              // no streaming home screen carries one. With the hero opening
              // the page it was also pushing the first row further down for
              // nothing.
              //
              // The search field owns the top inset instead: it is now the
              // first thing below the hero, and on a search it is the first
              // thing on the screen, so it has to clear the status bar
              // itself (the Scaffold sets top: false for the hero's sake).
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  _searchQuery.isEmpty
                      ? 16
                      : MediaQuery.of(context).padding.top + 12,
                  20,
                  10,
                ),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.ink.withValues(alpha: 0.1),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: AppType.body(colors.ink),
                    decoration: InputDecoration(
                      hintText: 'Global Search (Movies, Series, Live)',
                      hintStyle: AppType.body(
                        colors.ink.withValues(alpha: 0.38),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: colors.ink.withValues(alpha: 0.7),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.close,
                                color: colors.ink.withValues(alpha: 0.7),
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                _searchFocus.unfocus();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Main Content or Search Results
              if (_searchQuery.isNotEmpty)
                _buildSearchResults(content, userPrefs)
              else
                _buildHomeContent(content, userPrefs),
            ],
          ),
        ),
      ),
    );
  }

  /// Chooses what the hero shows, and routes its action.
  ///
  /// Continue Watching first — a half-finished episode is a better guess at
  /// what someone opened the app for than a new arrival. Falls back to the
  /// newest movie, then the newest series. Renders nothing at all rather than
  /// a placeholder if the provider has returned neither: an empty hero is
  /// worse than no hero.
  Widget _buildHero(ContentProvider content, UserPrefsProvider userPrefs) {
    final isArabic = userPrefs.locale == 'ar';

    if (userPrefs.history.isNotEmpty) {
      final item = userPrefs.history.first;
      return _HomeHero(
        title: item.title,
        imageUrl: item.posterUrl,
        meta: isArabic ? 'متابعة المشاهدة' : 'CONTINUE WATCHING',
        isResume: true,
        isArabic: isArabic,
        onOpen: () => _openHistoryItem(item),
      );
    }

    if (content.newMovies.isNotEmpty) {
      final movie = content.newMovies.first;
      return _HomeHero(
        title: movie.name,
        imageUrl: movie.streamIcon,
        meta: [
          movie.releaseDate,
          movie.genre,
        ].where((v) => v.isNotEmpty).join('  ·  '),
        isResume: false,
        isArabic: isArabic,
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MovieDetailsScreen(movie: movie)),
        ),
      );
    }

    if (content.newSeries.isNotEmpty) {
      final series = content.newSeries.first;
      return _HomeHero(
        title: series.name,
        imageUrl: series.cover,
        meta: [
          series.releaseDate,
          series.genre,
        ].where((v) => v.isNotEmpty).join('  ·  '),
        isResume: false,
        isArabic: isArabic,
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesDetailsScreen(series: series),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildHomeContent(
    ContentProvider content,
    UserPrefsProvider userPrefs,
  ) {
    final isArabic = userPrefs.locale == 'ar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Continue Watching Section (History)
        _buildSectionHeader(
          isArabic ? 'متابعة المشاهدة' : 'Continue Watching',
          '',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _HistoryCard.totalHeight,
          child: userPrefs.history.isEmpty
              ? StateView(
                  icon: Icons.play_circle_outline_rounded,
                  title: isArabic ? 'لا شيء بعد' : 'Nothing yet',
                  message: isArabic
                      ? 'ما تبدأ مشاهدته سيظهر هنا.'
                      : 'Anything you start watching shows up here.',
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: userPrefs.history.length,
                  itemBuilder: (context, index) {
                    final item = userPrefs.history[index];
                    return _buildHistoryCard(context, item);
                  },
                ),
        ),
        const SizedBox(height: 24),

        // New Series Section
        _buildSectionHeader(
          isArabic ? 'مسلسلات جديدة' : 'New Series',
          isArabic ? 'عرض الكل' : 'See All',
          onActionTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SeriesScreen(
                  title: isArabic ? 'مسلسلات جديدة' : 'New Series',
                  predefinedList: content.newSeries,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _PosterCard.totalHeight,
          child: content.isLoadingNewContent
              // A skeleton, not a spinner: the row geometry is known, so the
              // placeholder can be the shape of what is arriving and nothing
              // shifts when it does.
              ? const SkeletonRow()
              : (content.newSeries.isEmpty
                    ? StateView(
                        icon: Icons.video_library_outlined,
                        title: isArabic ? 'لا شيء هنا' : 'Nothing here',
                        message: isArabic
                            ? 'لم يُرجع مزودك أي عناوين في هذا القسم.'
                            : 'Your provider returned no titles for this '
                                  'section.',
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: content.newSeries.length,
                        itemBuilder: (context, index) {
                          final series = content.newSeries[index];
                          return _buildSeriesCard(context, series);
                        },
                      )),
        ),

        const SizedBox(height: 24),

        // New Movies Section
        _buildSectionHeader(
          isArabic ? 'أفلام جديدة' : 'New Movies',
          isArabic ? 'عرض الكل' : 'See All',
          onActionTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MoviesScreen(
                  title: isArabic ? 'أفلام جديدة' : 'New Movies',
                  predefinedList: content.newMovies,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _PosterCard.totalHeight,
          child: content.isLoadingNewContent
              // A skeleton, not a spinner: the row geometry is known, so the
              // placeholder can be the shape of what is arriving and nothing
              // shifts when it does.
              ? const SkeletonRow()
              : (content.newMovies.isEmpty
                    ? StateView(
                        icon: Icons.movie_outlined,
                        title: isArabic ? 'لا شيء هنا' : 'Nothing here',
                        message: isArabic
                            ? 'لم يُرجع مزودك أي عناوين في هذا القسم.'
                            : 'Your provider returned no titles for this '
                                  'section.',
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: content.newMovies.length,
                        itemBuilder: (context, index) {
                          final movie = content.newMovies[index];
                          return _buildMovieCard(context, movie);
                        },
                      )),
        ),
      ],
    );
  }

  Widget _buildSearchResults(
    ContentProvider content,
    UserPrefsProvider userPrefs,
  ) {
    final colors = context.colors;
    if (content.isLoadingAllContent) {
      return Padding(
        padding: const EdgeInsets.all(40.0),
        child: Center(
          child: CircularProgressIndicator(color: colors.brandPrimary),
        ),
      );
    }

    final results = content.searchAll(_searchQuery);
    final isArabic = userPrefs.locale == 'ar';

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: StateView(
          icon: Icons.search_off_rounded,
          title: isArabic ? 'لا توجد نتائج' : 'No results',
          message: isArabic
              ? 'لم يعثر مزودك على أي شيء بهذا الاسم. جرّب كلمة أقصر.'
              : 'Your provider returned nothing for that. Try a shorter word.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (results.movies.isNotEmpty) ...[
          _buildSectionHeader(isArabic ? 'الأفلام' : 'Movies', ''),
          const SizedBox(height: 12),
          SizedBox(
            height: _PosterCard.totalHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: results.movies.length,
              itemBuilder: (context, index) =>
                  _buildMovieCard(context, results.movies[index]),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (results.series.isNotEmpty) ...[
          _buildSectionHeader(isArabic ? 'المسلسلات' : 'Series', ''),
          const SizedBox(height: 12),
          SizedBox(
            height: _PosterCard.totalHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: results.series.length,
              itemBuilder: (context, index) =>
                  _buildSeriesCard(context, results.series[index]),
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (results.liveStreams.isNotEmpty) ...[
          _buildSectionHeader(isArabic ? 'البث المباشر' : 'Live TV', ''),
          const SizedBox(height: 12),
          SizedBox(
            height: _LiveCardMetrics.totalHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: results.liveStreams.length,
              itemBuilder: (context, index) => _buildLiveCard(
                context,
                results.liveStreams[index],
                results.liveStreams,
                index,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildLiveCard(
    BuildContext context,
    XtreamLiveStream live,
    List<XtreamLiveStream> allStreams,
    int index,
  ) {
    final colors = context.colors;
    return TvFocusable(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        final playlist = allStreams.map((l) {
          return {
            'url': l.streamUrl(
              context.read<ContentProvider>().baseUrl,
              context.read<ContentProvider>().username,
              context.read<ContentProvider>().password,
            ),
            'title': l.name,
            'coverUrl': l.streamIcon,
            'isLive': true,
          };
        }).toList();

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              streamUrl: playlist[index]['url'] as String,
              title: playlist[index]['title'] as String,
              coverUrl: playlist[index]['coverUrl'] as String,
              isLive: true,
              playlist: playlist,
              initialIndex: index,
            ),
          ),
        );
      },
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 132,
                // 16:9, matching how channel artwork is actually shaped —
                // the 2:3 poster frame cropped most logos.
                height: 74,
                color: colors.surfaceMuted,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (live.streamIcon.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: live.streamIcon,
                        fit: BoxFit.contain,
                        errorWidget: (_, _, _) => Icon(
                          Icons.live_tv,
                          color: colors.ink.withValues(alpha: 0.24),
                        ),
                      )
                    else
                      Icon(
                        Icons.live_tv,
                        color: colors.ink.withValues(alpha: 0.24),
                      ),
                    // The one place cyan appears in the app. Reserving a hue
                    // for a single meaning is what makes it read as a signal
                    // rather than decoration.
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: colors.brandAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text('LIVE', style: AppType.meta(Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: _LiveCardMetrics.captionHeight,
              child: Text(
                live.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption(colors.ink.withValues(alpha: 0.86)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A row header — type and a chevron, nothing else.
  ///
  /// This was a filled `surfaceMuted` box, which gave every section the same
  /// visual weight as a content card and flattened the page. Streaming rows
  /// are titled with plain type; the container was doing no work.
  Widget _buildSectionHeader(
    String title,
    String actionText, {
    VoidCallback? onActionTap,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.rowHeader(colors.ink),
            ),
          ),
          if (actionText.isNotEmpty)
            GestureDetector(
              onTap: onActionTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: colors.ink.withValues(alpha: 0.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, HistoryItem item) {
    return TvFocusable(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _openHistoryItem(item),
      child: _HistoryCard(item: item),
    );
  }

  /// Opens the detail page for a history entry.
  ///
  /// Shared by the Continue Watching card and the hero rather than
  /// duplicated: the detail page already owns resume — it offers the resume
  /// dialog on arrival — so routing there is both less code and the correct
  /// behaviour. A hero that started playback itself would need its own copy
  /// of the URL building and resume handling.
  void _openHistoryItem(HistoryItem item) {
    if (item.type == MediaType.movie) {
      final movie = XtreamVodStream.fromJson(item.rawData);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MovieDetailsScreen(movie: movie)),
      );
    } else if (item.type == MediaType.series) {
      // Because rawData could be the episode or the series depending on how it was stored,
      // Let's create a stub series from the raw data if it was stored properly.
      // In series_details_screen we stored: series_id, name, cover, etc.
      final series = XtreamSeries(
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
            int.tryParse(item.rawData['last_modified']?.toString() ?? '0') ?? 0,
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SeriesDetailsScreen(series: series)),
      );
    }
  }

  Widget _buildSeriesCard(BuildContext context, XtreamSeries series) {
    return _PosterCard(
      title: series.name,
      imageUrl: series.cover,
      rating: series.rating,
      fallbackIcon: Icons.video_library_outlined,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SeriesDetailsScreen(series: series)),
      ),
    );
  }

  Widget _buildMovieCard(BuildContext context, XtreamVodStream movie) {
    return _PosterCard(
      title: movie.name,
      imageUrl: movie.streamIcon,
      rating: movie.rating,
      fallbackIcon: Icons.movie_outlined,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MovieDetailsScreen(movie: movie)),
      ),
    );
  }
}

/// The one poster card behind every 2:3 row on this screen.
///
/// Geometry is fixed at 116x174 so rows line up across sections, and the
/// caption gets exactly two lines beneath the artwork — enough for a long
/// title, bounded so a row never grows a ragged bottom edge.
class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.title,
    required this.imageUrl,
    required this.onTap,
    required this.fallbackIcon,
    this.rating = '',
  });

  static const double width = 116;
  static const double posterHeight = 174;

  /// Two caption lines, in a fixed box. Not derived from the text style: the
  /// rendered height of two lines depends on the font's own metrics plus the
  /// device's text-scale setting, so a computed value is a prediction rather
  /// than arithmetic. Fixed means an oversized caption clips instead of
  /// overflowing its row.
  static const double captionHeight = 34;

  /// What a row's SizedBox has to be tall enough for.
  ///
  /// Includes TvFocusable's always-painted focus ring: every card is wrapped
  /// in one, and the ring is 3px on each edge whether or not it is visible.
  /// Leaving it out is what overflowed these rows by exactly 6px.
  static const double totalHeight =
      posterHeight + 8 + captionHeight + TvFocusable.focusInset;

  final String title;
  final String imageUrl;
  final String rating;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  /// Panels report "0" (and sometimes "0.0" or an empty string) for anything
  /// unrated, which rendered as a black `0` badge on most of the grid.
  bool get _hasRating {
    final value = double.tryParse(rating);
    return rating.isNotEmpty && value != null && value > 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TvFocusable(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: width,
                height: posterHeight,
                color: colors.surfaceMuted,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Icon(
                          fallbackIcon,
                          color: colors.ink.withValues(alpha: 0.24),
                        ),
                      )
                    else
                      Icon(
                        fallbackIcon,
                        color: colors.ink.withValues(alpha: 0.24),
                      ),
                    // Rating stays on the artwork: it is a badge, not a label,
                    // and it reads fine against any image at this size.
                    if (_hasRating)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            rating,
                            style: AppType.meta(Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: captionHeight,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption(colors.ink.withValues(alpha: 0.86)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Continue Watching: a 16:9 still with the progress bar *inside* the
/// artwork's bottom edge.
///
/// Progress belongs on the image, not under it — it is the single most
/// recognised affordance in streaming, and putting it below turns a glanceable
/// mark into another row of chrome.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});

  static const double width = 160;
  static const double stillHeight = 90;
  static const double captionHeight = 34;
  static const double totalHeight =
      stillHeight + 8 + captionHeight + TvFocusable.focusInset;

  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = item.durationMilliseconds > 0
        ? (item.positionMilliseconds / item.durationMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: width,
              height: stillHeight,
              color: colors.surfaceMuted,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.posterUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Icon(
                        Icons.play_circle_outline,
                        color: colors.ink.withValues(alpha: 0.24),
                      ),
                    )
                  else
                    Icon(
                      Icons.play_circle_outline,
                      color: colors.ink.withValues(alpha: 0.24),
                    ),
                  if (progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 3,
                        color: Colors.black.withValues(alpha: 0.45),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: ColoredBox(color: colors.brandPrimary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: captionHeight,
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption(colors.ink.withValues(alpha: 0.86)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Geometry for the live channel card, kept beside the poster metrics so a
/// row's SizedBox never has to guess.
class _LiveCardMetrics {
  const _LiveCardMetrics._();
  static const double artworkHeight = 74;
  static const double captionHeight = 34;
  static const double totalHeight =
      artworkHeight + 8 + captionHeight + TvFocusable.focusInset;
}

/// The full-bleed opener at the top of Home.
///
/// The screen previously began with a wordmark, a search field and then rows
/// — which reads as a catalogue browser rather than a place to watch
/// something. Every service in this category opens on one title at full
/// width, because the first job of a home screen is to answer "what am I
/// watching now", not "what would you like to search for".
///
/// The subject is whatever the viewer is partway through, falling back to the
/// newest thing the provider has. Continue Watching first is deliberate: a
/// half-finished episode is a far better guess at intent than a new arrival.
///
/// One action, not two. The brief's benchmark pairs Play with More info, but
/// both would land on the same detail page here — this hero routes there
/// rather than starting playback itself, because that page already owns
/// resume and the URL building. Two controls with one destination is worse
/// than one honest control.
class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.title,
    required this.imageUrl,
    required this.meta,
    required this.isResume,
    required this.isArabic,
    required this.onOpen,
  });

  final String title;
  final String imageUrl;
  final String meta;
  final bool isResume;
  final bool isArabic;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);

    // Just under half the viewport, which leaves the first content row
    // peeking above the fold — the cue that tells a viewer to keep
    // scrolling. A full-height opener hides the rest of the app.
    final height = (media.size.height * 0.46).clamp(280.0, 460.0);

    return GestureDetector(
      onTap: onOpen,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                // Xtream exposes no backdrop field — the models carry only
                // the 2:3 poster (see XtreamVodStream.streamIcon and
                // XtreamSeries.cover), so this is a portrait image filling a
                // near-square box. Aligned to the top rather than centred
                // because key art puts its subject in the upper half, and a
                // centred crop takes the bottom of a face and the top of a
                // title block.
                alignment: Alignment.topCenter,
                errorWidget: (_, _, _) =>
                    ColoredBox(color: colors.surfaceMuted),
              )
            else
              ColoredBox(color: colors.surfaceMuted),

            // Two stops, not a wash across the whole image: the artwork stays
            // legible down to 40% and only then falls to the page ground, so
            // the hero joins the rows beneath it without a visible seam.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    colors.background.withValues(alpha: 0.55),
                    colors.background,
                  ],
                  stops: const [0.40, 0.78, 1.0],
                ),
              ),
            ),

            Positioned(
              left: 20,
              right: 20,
              bottom: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.hero(colors.ink),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta(colors.ink.withValues(alpha: 0.65)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Solid ink on a dark ground is the highest-contrast
                  // control the palette allows, which is what the one
                  // primary action on the screen should be.
                  ElevatedButton.icon(
                    onPressed: onOpen,
                    icon: Icon(
                      isResume
                          ? Icons.play_arrow_rounded
                          : Icons.info_outline_rounded,
                      color: colors.background,
                      size: 22,
                    ),
                    label: Text(
                      isResume
                          ? (isArabic ? 'متابعة' : 'Resume')
                          : (isArabic ? 'التفاصيل' : 'More info'),
                      style: AppType.label(colors.background),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.ink,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
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
