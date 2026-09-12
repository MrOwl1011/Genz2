import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/user_prefs_provider.dart';
import '../../screens/player_screen.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import '../widgets/tv_focus.dart';
import 'tv_movie_detail_screen.dart';
import 'tv_series_detail_screen.dart';

/// Everything the viewer has hearted, in a row per kind: Movies, Series and
/// Live channels.
///
/// Rows rather than one mixed grid, because the three open onto different
/// things — a movie and a series have detail pages, a live channel goes
/// straight to the player — and a single grid gave no clue which a poster
/// was. Horizontal rows also suit a D-pad: left and right move within a
/// kind, up and down between kinds.
class TvFavoritesScreen extends StatefulWidget {
  const TvFavoritesScreen({super.key});

  @override
  State<TvFavoritesScreen> createState() => _TvFavoritesScreenState();
}

/// A row's height and each card's width. The card sizes its poster with an
/// Expanded, so the row has to give it a bounded height.
const double _cardWidth = 150;
const double _cardHeight = 250;

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
    } else if (item.type == MediaType.live) {
      // A channel has no detail page — the same direct-to-player route the
      // Live screen uses.
      final content = context.read<ContentProvider>();
      final channel = XtreamLiveStream.fromJson(item.rawData);
      await pushTv(
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
        ),
      );
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
    final favorites = userPrefs.favorites;
    final sections = <({String title, List<FavoriteItem> items})>[
      (
        title: isArabic ? 'أفلام' : 'MOVIES',
        items: favorites.where((f) => f.type == MediaType.movie).toList(),
      ),
      (
        title: isArabic ? 'مسلسلات' : 'SERIES',
        items: favorites.where((f) => f.type == MediaType.series).toList(),
      ),
      (
        title: isArabic ? 'قنوات مباشرة' : 'LIVE CHANNELS',
        items: favorites.where((f) => f.type == MediaType.live).toList(),
      ),
    ].where((s) => s.items.isNotEmpty).toList();

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
                        color: focused ? colors.ink : colors.ink,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isArabic ? 'المفضلة' : 'FAVORITES',
                    style: AppType.heroTv(colors.ink).copyWith(fontSize: 30),
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
                  child: sections.isEmpty
                      ? Center(
                          child: Text(
                            isArabic
                                ? 'لا توجد عناصر في المفضلة بعد.'
                                : 'Nothing in your favorites yet.',
                            style: AppType.title(
                              colors.ink.withValues(alpha: 0.45),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          itemCount: sections.length,
                          itemBuilder: (context, sectionIndex) {
                            final section = sections[sectionIndex];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    section.title,
                                    style: AppType.meta(
                                      colors.ink.withValues(alpha: 0.55),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: _cardHeight,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: section.items.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: TvMetrics.gap),
                                    itemBuilder: (context, index) {
                                      final item = section.items[index];
                                      return SizedBox(
                                        width: _cardWidth,
                                        child: _FavoriteCard(
                                          // Stable, item-derived key — see
                                          // tv_media_grid_screen.dart's
                                          // identical fix (favorites reorder
                                          // as items are un-hearted while
                                          // one is focused).
                                          key: ValueKey(item.id),
                                          item: item,
                                          autofocus:
                                              sectionIndex == 0 && index == 0,
                                          onTap: () => _open(context, item),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                SizedBox(height: TvMetrics.gap + 6),
                              ],
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
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused ? colors.ink : Colors.transparent,
                width: 3,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: colors.brandPrimary.withValues(alpha: 0.5),
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
                  style: AppType.bodySmall(
                    focused ? colors.ink : colors.ink.withValues(alpha: 0.8),
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
