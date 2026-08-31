import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/xtream_models.dart';
import '../../providers/user_prefs_provider.dart';
import '../../theme/app_colors.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import '../widgets/tv_focus.dart';
import 'tv_movie_detail_screen.dart';
import 'tv_series_detail_screen.dart';

/// The Favorites destination from the TV home hub: a D-pad navigable poster
/// grid over everything the user has hearted, movies and series together.
class TvFavoritesScreen extends StatefulWidget {
  const TvFavoritesScreen({super.key});

  @override
  State<TvFavoritesScreen> createState() => _TvFavoritesScreenState();
}

class _TvFavoritesScreenState extends State<TvFavoritesScreen> {
  // Same mechanism as TvMediaGridScreen's _lastGridFocus — see its doc
  // comment. This screen is likewise never popped while a detail screen is
  // pushed on top of it, so the same exact-node-reuse approach applies.
  FocusNode? _lastGridFocus;

  void _handleGridFocusChange(bool hasFocus) {
    if (hasFocus) _lastGridFocus = FocusManager.instance.primaryFocus;
  }

  Future<void> _open(BuildContext context, FavoriteItem item) async {
    if (item.type == MediaType.movie) {
      final movie = XtreamVodStream.fromJson(item.rawData);
      await pushTv(context, TvMovieDetailScreen(movie: movie));
    } else if (item.type == MediaType.series) {
      // Favorited series store the series payload directly (see
      // series_details_screen's toggleFavorite call), but fall back to the
      // item's own fields so an older/partial entry still opens.
      final series = XtreamSeries(
        seriesId: item.rawData['series_id'] ?? int.tryParse(item.id) ?? 0,
        name: item.rawData['name'] ?? item.title,
        cover: item.rawData['cover'] ?? item.posterUrl,
        categoryId: item.rawData['category_id']?.toString() ?? '',
        plot: item.rawData['plot']?.toString() ?? '',
        cast: item.rawData['cast']?.toString() ?? '',
        director: item.rawData['director']?.toString() ?? '',
        genre: item.rawData['genre']?.toString() ?? '',
        releaseDate: item.rawData['releaseDate']?.toString() ?? '',
        rating: item.rawData['rating']?.toString() ?? '',
        lastModified:
            int.tryParse(item.rawData['last_modified']?.toString() ?? '0') ?? 0,
      );
      await pushTv(context, TvSeriesDetailScreen(series: series));
    }
    if (mounted) {
      final node = _lastGridFocus;
      if (node != null && node.canRequestFocus) node.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final userPrefs = context.watch<UserPrefsProvider>();
    final isArabic = userPrefs.locale == 'ar';
    // Live TV favorites open in the player rather than a details screen, so
    // this grid covers the two that have one.
    final items = userPrefs.favorites
        .where((f) => f.type == MediaType.movie || f.type == MediaType.series)
        .toList();

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
        child: Padding(
          padding: TvMetrics.safeArea,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TvFocusScope(
                    onTap: () => Navigator.of(context).pop(),
                    builder: (context, focused) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: focused ? colors.brandAccent : colors.ink,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isArabic ? 'المفضلة' : 'FAVORITES',
                    style: GoogleFonts.outfit(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: colors.ink,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Focus(
                  // Observer only — see _lastGridFocus's doc comment.
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: _handleGridFocusChange,
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            isArabic
                                ? 'لا توجد عناصر في المفضلة بعد.'
                                : 'Nothing in your favorites yet.',
                            style: GoogleFonts.outfit(
                              color: colors.ink.withValues(alpha: 0.45),
                              fontSize: 18,
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 6,
                                childAspectRatio: 0.62,
                                crossAxisSpacing: TvMetrics.gap,
                                mainAxisSpacing: TvMetrics.gap,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return _FavoriteCard(
                              // Stable, item-derived key — see
                              // tv_media_grid_screen.dart's identical fix
                              // for the reasoning (favorites can reorder as
                              // items are un-hearted while one is focused).
                              key: ValueKey(item.id),
                              item: item,
                              autofocus: index == 0,
                              onTap: () => _open(context, item),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final FavoriteItem item;
  final VoidCallback onTap;
  final bool autofocus;

  const _FavoriteCard({
    super.key,
    required this.item,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TvFocusScope(
      onTap: onTap,
      autofocus: autofocus,
      builder: (context, focused) {
        return AnimatedScale(
          scale: focused ? TvMetrics.focusScale : 1,
          duration: TvMetrics.focusAnim,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: TvMetrics.focusAnim,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused ? colors.brandAccent : Colors.transparent,
                width: 3,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: colors.brandAccent.withValues(alpha: 0.5),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: item.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.posterUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorWidget: (_, _, _) => Container(
                              color: colors.surfaceMuted,
                              child: Icon(
                                Icons.movie_rounded,
                                color: colors.ink.withValues(alpha: 0.24),
                              ),
                            ),
                          )
                        : Container(
                            color: colors.surfaceMuted,
                            child: Icon(
                              Icons.movie_rounded,
                              color: colors.ink.withValues(alpha: 0.24),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: focused
                        ? colors.brandAccent
                        : colors.ink.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
