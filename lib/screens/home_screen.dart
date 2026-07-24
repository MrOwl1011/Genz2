import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/content_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../models/xtream_models.dart';
import '../widgets/category_layout.dart';
import 'series_screen.dart';
import 'movies_screen.dart';
import 'movie_details_screen.dart';
import 'series_details_screen.dart';
import 'player_screen.dart';

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
                  child: Text(
                    'GenZ+',
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFE50914),
                      letterSpacing: 4,
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
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Global Search (Movies, Series, Live)',
                      hintStyle: GoogleFonts.outfit(color: Colors.white38),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white70,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Continue Watching Section (History)
        _buildSectionHeader(isArabic ? 'متابعة المشاهدة' : 'Continue Watching', ''),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: userPrefs.history.isEmpty
              ? Center(
                  child: Text(
                    isArabic ? 'لا يوجد سجل متاح' : 'No History Available',
                    style: const TextStyle(color: Colors.white54),
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
          height: 180,
          child: content.isLoadingNewContent
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                )
              : (content.newSeries.isEmpty
                    ? Center(
                        child: Text(
                          isArabic ? 'لا توجد مسلسلات متاحة' : 'No Series Available',
                          style: const TextStyle(color: Colors.white54),
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
          height: 180,
          child: content.isLoadingNewContent
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                )
              : (content.newMovies.isEmpty
                    ? Center(
                        child: Text(
                          isArabic ? 'لا توجد أفلام متاحة' : 'No Movies Available',
                          style: const TextStyle(color: Colors.white54),
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

  Widget _buildSearchResults(ContentProvider content, UserPrefsProvider userPrefs) {
    if (content.isLoadingAllContent) {
      return const Padding(
        padding: EdgeInsets.all(40.0),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFE50914)),
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
            style: const TextStyle(color: Colors.white54),
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
            height: 180,
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
            height: 180,
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
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: results.liveStreams.length,
              itemBuilder: (context, index) =>
                  _buildLiveCard(context, results.liveStreams[index], results.liveStreams, index),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildLiveCard(BuildContext context, XtreamLiveStream live, List<XtreamLiveStream> allStreams, int index) {
    return GestureDetector(
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
          color: const Color(0xFF1E1E1E),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            live.streamIcon.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: live.streamIcon,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const Icon(Icons.live_tv, color: Colors.white24),
                  )
                : const Icon(Icons.live_tv, color: Colors.white24),
            // Title overlay
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
                  style: GoogleFonts.outfit(
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

  Widget _buildSectionHeader(
    String title,
    String actionText, {
    VoidCallback? onActionTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20.0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Dark grey card background
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (actionText.isNotEmpty)
            GestureDetector(
              onTap: onActionTap,
              child: Text(
                actionText,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE50914), // Red action text
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, HistoryItem item) {
    return GestureDetector(
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
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF1E1E1E),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            item.posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: item.posterUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const Icon(Icons.movie, color: Colors.white24),
                  )
                : const Icon(Icons.movie, color: Colors.white24),
            // Title overlay
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Progress bar
                    if (item.durationMilliseconds > 0)
                      LinearProgressIndicator(
                        value: (item.positionMilliseconds / item.durationMilliseconds)
                            .clamp(0.0, 1.0),
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFE50914),
                        ),
                        minHeight: 3,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeriesCard(BuildContext context, XtreamSeries series) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesDetailsScreen(series: series),
          ),
        );
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF1E1E1E),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            series.cover.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: series.cover,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const Icon(Icons.movie, color: Colors.white24),
                  )
                : const Icon(Icons.movie, color: Colors.white24),
            // Title overlay
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
                  series.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
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

  Widget _buildMovieCard(BuildContext context, XtreamVodStream movie) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MovieDetailsScreen(movie: movie)),
        );
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF1E1E1E),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            movie.streamIcon.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: movie.streamIcon,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const Icon(Icons.movie, color: Colors.white24),
                  )
                : const Icon(Icons.movie, color: Colors.white24),
            // Title overlay
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
                  movie.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Rating badge on top left
            if (movie.rating.isNotEmpty)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_outline,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        movie.rating,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlantedButton(BuildContext context, String title, int tabIndex) {
    // We can use a slanted container using Transform.skew
    return GestureDetector(
      onTap: () {
        // Need to change the tab of MainNavigation.
        // We can do this by finding the state of MainNavigation (though not ideal if it's far up the tree).
        // Since we are inside MainNavigation, we can use an event or provider.
        // For now, let's try pushing the actual screen just to see it work,
        // or if possible, we should communicate with MainNavigation via an inherited widget or provider.
        // Because MainNavigation controls the index, we can't easily change it without a GlobalKey or Provider.
        // For this UI mockup, I'll just show the visual button.
      },
      child: Transform(
        transform: Matrix4.skewX(-0.3), // Slant to the left
        alignment: Alignment.center,
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            border: Border.all(color: const Color(0xFF350000), width: 2),
          ),
          alignment: Alignment.center,
          child: Transform(
            transform: Matrix4.skewX(0.3), // Un-slant the text
            alignment: Alignment.center,
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
