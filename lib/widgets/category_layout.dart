import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/build_flavor.dart' show kIsTv;
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../screens/movie_details_screen.dart';
import '../screens/series_details_screen.dart';
import '../theme/app_colors.dart';
import 'category_card.dart';
import '../screens/player_screen.dart';
import 'tv_focusable.dart';
import 'tv_search_field.dart';

class CategoryLayout extends StatefulWidget {
  final String title;
  final List<XtreamCategory> categories;
  final CategoryType type;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;
  final void Function(XtreamCategory) onCategoryTap;
  final List<String> tabs;

  const CategoryLayout({
    super.key,
    required this.title,
    required this.categories,
    required this.type,
    required this.isLoading,
    this.error,
    required this.onRetry,
    required this.onCategoryTap,
    this.tabs = const ['All', 'Liked', 'New', 'History'],
  });

  @override
  State<CategoryLayout> createState() => _CategoryLayoutState();
}

class _CategoryLayoutState extends State<CategoryLayout> {
  int _selectedTab = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
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
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCategories = widget.categories
        .where(
          (c) =>
              c.categoryName.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';
    final searchHint = isArabic
        ? 'ابحث عن ${widget.type == CategoryType.movie
              ? 'أفلام'
              : widget.type == CategoryType.series
              ? 'مسلسلات'
              : 'قنوات'}'
        : 'Search ${widget.type == CategoryType.movie
              ? 'Movies'
              : widget.type == CategoryType.series
              ? 'Series'
              : 'Channels'}';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors.backgroundGradient,
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Title — on TV, LiveScreen is pushed as its own route
              // (see TvHomeScreen._pushSection) rather than living as a
              // permanent bottom-nav tab the way it does on phone, so it
              // needs an explicit way back that the phone tab never does.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  children: [
                    if (kIsTv)
                      TvFocusable(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: colors.ink,
                            size: 26,
                          ),
                        ),
                      ),
                    Text(
                      widget.title.toUpperCase(),
                      style: GoogleFonts.archivo(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        color: colors.ink,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),

              // Search Bar & Refresh
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: kIsTv
                          // TV: a plain TextField here would suffer the
                          // same on-screen-keyboard-hijacks-D-pad bug the
                          // login screen had — see TvSearchField's own doc
                          // comment for the full mechanism.
                          ? TvSearchField(
                              controller: _searchController,
                              hint: searchHint,
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val),
                              onClose: _searchQuery.isEmpty
                                  ? null
                                  : () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                            )
                          : Container(
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
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val),
                                style: GoogleFonts.archivo(color: colors.ink),
                                decoration: InputDecoration(
                                  hintText: searchHint,
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
                                            color: colors.ink.withValues(
                                              alpha: 0.7,
                                            ),
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 50,
                      width: 50,
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colors.ink.withValues(alpha: 0.1),
                        ),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.refresh_rounded,
                          color: colors.ink.withValues(alpha: 0.7),
                        ),
                        onPressed: widget.onRetry,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Slanted Tabs
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: widget.tabs.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedTab;
                    return TvFocusable(
                      onTap: () => setState(() => _selectedTab = index),
                      borderRadius: BorderRadius.zero,
                      child: Transform(
                        transform: Matrix4.skewX(-0.25),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.brandPrimary
                                : colors.surfaceMuted,
                          ),
                          alignment: Alignment.center,
                          child: Transform(
                            transform: Matrix4.skewX(0.25),
                            child: Text(
                              widget.tabs[index],
                              style: GoogleFonts.archivo(
                                color: isSelected
                                    ? Colors.white
                                    : colors.ink.withValues(alpha: 0.7),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Content
              Expanded(child: _buildContent(filteredCategories)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<XtreamCategory> categories) {
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';
    if (widget.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
        ),
      );
    }

    if (widget.error != null) {
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
              widget.error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.archivo(
                color: colors.ink.withValues(alpha: 0.54),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: widget.onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.brandPrimary,
              ),
              child: Text(isArabic ? 'إعادة المحاولة' : 'Retry'),
            ),
          ],
        ),
      );
    }

    final content = context.watch<ContentProvider>();
    final userPrefs = context.watch<UserPrefsProvider>();
    final targetMediaType = switch (widget.type) {
      CategoryType.movie => MediaType.movie,
      CategoryType.series => MediaType.series,
      CategoryType.live => MediaType.live,
    };

    List<dynamic> items = [];

    // If there is an active search
    if (_searchQuery.isNotEmpty) {
      if (content.isLoadingAllContent) {
        return Center(
          child: CircularProgressIndicator(color: colors.brandPrimary),
        );
      }

      if (_selectedTab == 0) {
        // Search globally within this partition type
        final results = content.searchAll(_searchQuery);
        if (widget.type == CategoryType.movie) {
          items = results.movies;
        } else if (widget.type == CategoryType.series) {
          items = results.series;
        } else {
          items = results.liveStreams;
        }
      } else {
        // Search within the specific tab (Liked/New/History)
        if (_selectedTab == 1) {
          items = userPrefs.favorites
              .where((f) => f.type == targetMediaType)
              .map((f) => f.rawData)
              .toList();
        } else if (_selectedTab == 2) {
          items = widget.type == CategoryType.movie
              ? content.newMovies
              : content.newSeries;
        } else if (_selectedTab == 3) {
          items = userPrefs.history
              .where((h) => h.type == targetMediaType)
              .map((h) => h.rawData)
              .toList();
        }

        final lowerQuery = _searchQuery.toLowerCase();
        items = items.where((item) {
          String name = '';
          if (item is XtreamVodStream) {
            name = item.name;
          } else if (item is XtreamSeries)
            name = item.name;
          else if (item is XtreamLiveStream)
            name = item.name;
          else if (item is Map<String, dynamic>)
            name = item['series_name'] ?? item['name'] ?? item['title'] ?? '';
          return name.toLowerCase().contains(lowerQuery);
        }).toList();
      }

      if (items.isEmpty) {
        return Center(
          child: Text(
            isArabic ? 'لا توجد نتائج.' : 'No results found.',
            style: GoogleFonts.archivo(
              color: colors.ink.withValues(alpha: 0.38),
              fontSize: 16,
            ),
          ),
        );
      }
    } else {
      // Normal display without search
      if (_selectedTab == 0) {
        if (categories.isEmpty) {
          return Center(
            child: Text(
              isArabic ? 'لا توجد فئات.' : 'No categories found.',
              style: GoogleFonts.archivo(
                color: colors.ink.withValues(alpha: 0.38),
                fontSize: 16,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            return CategoryCard(
              category: categories[index],
              type: widget.type,
              onTap: () => widget.onCategoryTap(categories[index]),
            );
          },
        );
      } else if (_selectedTab == 1) {
        items = userPrefs.favorites
            .where((f) => f.type == targetMediaType)
            .map((f) => f.rawData)
            .toList();
      } else if (_selectedTab == 2) {
        items = widget.type == CategoryType.movie
            ? content.newMovies
            : content.newSeries;
      } else if (_selectedTab == 3) {
        items = userPrefs.history
            .where((h) => h.type == targetMediaType)
            .map((h) => h.rawData)
            .toList();
      }

      if (items.isEmpty) {
        return Center(
          child: Text(
            isArabic
                ? 'لا توجد عناصر في هذا القسم.'
                : 'No items available in this section.',
            style: GoogleFonts.archivo(
              color: colors.ink.withValues(alpha: 0.38),
              fontSize: 16,
            ),
          ),
        );
      }
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final rawItem = items[index];
        if (widget.type == CategoryType.movie) {
          // Both newMovies and rawData (from Liked/History) can be handled.
          // Liked/History stores raw JSON map. newMovies is already XtreamVodStream.
          final movie = rawItem is XtreamVodStream
              ? rawItem
              : XtreamVodStream.fromJson(rawItem);
          return _buildMovieGridItem(movie);
        } else if (widget.type == CategoryType.live) {
          // Live Streams
          final live = rawItem is XtreamLiveStream
              ? rawItem
              : XtreamLiveStream.fromJson(rawItem);
          return _buildLiveGridItem(live, items, index);
        } else {
          // Series
          final series = rawItem is XtreamSeries
              ? rawItem
              : XtreamSeries(
                  seriesId:
                      rawItem['series_id'] ??
                      int.tryParse(rawItem['id']?.toString() ?? '0') ??
                      0,
                  name:
                      rawItem['series_name'] ??
                      rawItem['name'] ??
                      rawItem['title'] ??
                      '',
                  cover:
                      rawItem['series_cover'] ??
                      rawItem['cover'] ??
                      rawItem['posterUrl'] ??
                      '',
                  categoryId: rawItem['category_id']?.toString() ?? '',
                  plot: rawItem['plot'] ?? '',
                  cast: rawItem['cast'] ?? '',
                  director: rawItem['director'] ?? '',
                  genre: rawItem['genre'] ?? '',
                  releaseDate: rawItem['releaseDate'] ?? '',
                  rating: rawItem['rating']?.toString() ?? '',
                  lastModified:
                      int.tryParse(
                        rawItem['last_modified']?.toString() ?? '0',
                      ) ??
                      0,
                );
          return _buildSeriesGridItem(series);
        }
      },
    );
  }

  Widget _buildLiveGridItem(
    XtreamLiveStream live,
    List<dynamic> items,
    int index,
  ) {
    final colors = context.colors;
    return TvFocusable(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        final playlist = items.map((item) {
          final l = item is XtreamLiveStream
              ? item
              : XtreamLiveStream.fromJson(item as Map<String, dynamic>);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
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
                  // Scrim — fixed regardless of theme, sits directly on the
                  // poster image (see home_screen.dart for the same pattern).
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            live.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.archivo(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieGridItem(XtreamVodStream movie) {
    final colors = context.colors;
    return TvFocusable(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MovieDetailsScreen(movie: movie)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  movie.streamIcon.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: movie.streamIcon,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Icon(
                            Icons.movie,
                            color: colors.ink.withValues(alpha: 0.24),
                          ),
                        )
                      : Icon(
                          Icons.movie,
                          color: colors.ink.withValues(alpha: 0.24),
                        ),
                  // Scrim — fixed regardless of theme, see _buildLiveGridItem.
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            movie.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.archivo(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesGridItem(XtreamSeries series) {
    final colors = context.colors;
    return TvFocusable(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesDetailsScreen(series: series),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  series.cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: series.cover,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Icon(
                            Icons.movie,
                            color: colors.ink.withValues(alpha: 0.24),
                          ),
                        )
                      : Icon(
                          Icons.movie,
                          color: colors.ink.withValues(alpha: 0.24),
                        ),
                  // Scrim — fixed regardless of theme, see _buildLiveGridItem.
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            series.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.archivo(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
