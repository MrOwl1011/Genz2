import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/content_provider.dart';
import '../providers/auth_provider.dart';
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
    final auth = context.watch<AuthProvider>();
    final userPrefs = context.watch<UserPrefsProvider>();
    final colors = context.colors;

    return Scaffold(
      backgroundColor:
          Colors.transparent, // Background handled by MainNavigation
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(
            bottom: 100,
          ), // Spacing for floating navbar
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: colors.brandGradient,
                    ).createShader(bounds),
                    child: Text(
                      'GenZ+',
                      style: GoogleFonts.archivo(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 10.0,
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
                    style: GoogleFonts.archivo(color: colors.ink),
                    decoration: InputDecoration(
                      hintText: 'Global Search (Movies, Series, Live)',
                      hintStyle: GoogleFonts.archivo(
                        color: colors.ink.withValues(alpha: 0.38),
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

  Widget _buildHomeContent(
    ContentProvider content,
    UserPrefsProvider userPrefs,
  ) {
    final isArabic = userPrefs.locale == 'ar';
    final colors = context.colors;
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
              ? Center(
                  child: Text(
                    isArabic ? 'لا يوجد سجل متاح' : 'No History Available',
                    style: TextStyle(color: colors.ink.withValues(alpha: 0.54)),
                  ),
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
                    ? Center(
                        child: Text(
                          isArabic
                              ? 'لا توجد مسلسلات متاحة'
                              : 'No Series Available',
                          style: TextStyle(
                            color: colors.ink.withValues(alpha: 0.54),
                          ),
                        ),
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
                    ? Center(
                        child: Text(
                          isArabic
                              ? 'لا توجد أفلام متاحة'
                              : 'No Movies Available',
                          style: TextStyle(
                            color: colors.ink.withValues(alpha: 0.54),
                          ),
                        ),
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
        padding: const EdgeInsets.all(40.0),
        child: Center(
          child: Text(
            isArabic ? 'لا توجد نتائج.' : 'No results found.',
            style: TextStyle(color: colors.ink.withValues(alpha: 0.54)),
          ),
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
            height: _PosterCard.totalHeight,
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
      borderRadius: BorderRadius.circular(12),
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
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: colors.surfaceMuted,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            live.streamIcon.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: live.streamIcon,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Icon(
                      Icons.live_tv,
                      color: colors.ink.withValues(alpha: 0.24),
                    ),
                  )
                : Icon(
                    Icons.live_tv,
                    color: colors.ink.withValues(alpha: 0.24),
                  ),
            // Title overlay — fixed dark scrim for legibility over the poster
            // image itself, intentionally not theme-reactive (see player_screen
            // and category cards for the same pattern).
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black, Colors.transparent],
                  ),
                ),
                child: Text(
                  live.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.archivo(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
      borderRadius: BorderRadius.circular(12),
      onTap: () {
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
                int.tryParse(
                  item.rawData['last_modified']?.toString() ?? '0',
                ) ??
                0,
          );
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SeriesDetailsScreen(series: series),
            ),
          );
        }
      },
      child: _HistoryCard(item: item),
    );
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

  /// Artwork plus caption plus the gap between them — what a row's SizedBox
  /// has to be tall enough for.
  static const double totalHeight = posterHeight + 8 + 34;

  final String title;
  final String imageUrl;
  final String rating;
  final IconData fallbackIcon;
  final VoidCallback onTap;

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
                    if (rating.isNotEmpty)
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
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption(colors.ink.withValues(alpha: 0.86)),
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
  static const double totalHeight = stillHeight + 8 + 34;

  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = item.durationMilliseconds > 0
        ? (item.positionMilliseconds / item.durationMilliseconds)
              .clamp(0.0, 1.0)
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
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption(colors.ink.withValues(alpha: 0.86)),
          ),
        ],
      ),
    );
  }
}
