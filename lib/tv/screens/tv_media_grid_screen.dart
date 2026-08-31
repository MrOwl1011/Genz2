import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/user_prefs_provider.dart' show HistoryItem, MediaType;
import '../../theme/app_colors.dart';
import '../../widgets/category_card.dart' show CategoryType;
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_search_field.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import 'tv_movie_detail_screen.dart';
import 'tv_series_detail_screen.dart';

/// The TV-native poster grid for either a single category's content, an
/// already-resolved list of items (the Liked/New/History tabs upstream in
/// [TvCategoryListScreen] hand items straight in, since there's nothing left
/// to fetch for those), or a mixed-type watch history (items are
/// [HistoryItem]s in that case, each carrying its own movie/series type —
/// see [_open]'s handling of that, since [type]/[_isMovie] alone can't tell
/// a mixed list apart).
class TvMediaGridScreen extends StatefulWidget {
  final CategoryType type;
  final XtreamCategory? category;
  final String? title;
  final List<dynamic>? items;

  /// Opens with the search field already active and focused. Used by the
  /// home nav's search icon, whose whole purpose is to start typing.
  final bool openSearch;

  const TvMediaGridScreen({
    super.key,
    required this.type,
    this.category,
    this.title,
    this.items,
    this.openSearch = false,
  }) : assert(
         category != null || items != null || openSearch,
         'Needs a category to fetch, an explicit item list, or global-search '
         'mode (which fetches the whole library to filter locally).',
       );

  @override
  State<TvMediaGridScreen> createState() => _TvMediaGridScreenState();
}

class _TvMediaGridScreenState extends State<TvMediaGridScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  String? _error;
  bool _searchOpen = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  bool get _isMovie => widget.type == CategoryType.movie;

  // Restores D-pad focus to the exact tile the user opened after they back
  // out of the detail screen it pushed. This screen is never popped while
  // that detail screen is on top of it (a push, not a replace), so its
  // whole widget tree — including whichever tile's FocusNode this points
  // to — stays alive and un-disposed the entire time; simply re-requesting
  // focus on the same node once we're back is exact, and costs nothing
  // extra to maintain (no index bookkeeping, no re-derivation).
  FocusNode? _lastGridFocus;

  void _handleGridFocusChange(bool hasFocus) {
    if (hasFocus) _lastGridFocus = FocusManager.instance.primaryFocus;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _searchOpen = widget.openSearch;
    // An explicit item list (Liked/New/History, or search results handed
    // down) needs no fetch. Everything else does: a category fetches that
    // category, and global-search mode fetches the whole library once so
    // typing filters locally instead of re-querying per keystroke.
    if (widget.items != null && !widget.openSearch) {
      _items = widget.items!;
      _isLoading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final content = context.read<ContentProvider>();
      // A null categoryId asks the provider for everything of that type,
      // which is exactly what global search needs.
      final categoryId = widget.category?.categoryId;
      final result = _isMovie
          ? await content.getVodStreams(categoryId: categoryId)
          : await content.getSeriesList(categoryId: categoryId);
      if (!mounted) return;
      setState(() {
        _items = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _open(dynamic rawItem) async {
    // Watch history mixes movies and series in one list — each item knows
    // its own type, so it's used instead of widget.type/_isMovie (which
    // only make sense when the whole list is one kind, as it is for a
    // category grid or the Liked/New tabs).
    if (rawItem is HistoryItem) {
      if (rawItem.type == MediaType.movie) {
        await pushTv(
          context,
          TvMovieDetailScreen(movie: XtreamVodStream.fromJson(rawItem.rawData)),
        );
      } else if (rawItem.type == MediaType.series) {
        await pushTv(
          context,
          TvSeriesDetailScreen(series: _seriesFromMap(rawItem.rawData)),
        );
      }
    } else if (_isMovie) {
      final movie = rawItem is XtreamVodStream
          ? rawItem
          : XtreamVodStream.fromJson(rawItem as Map<String, dynamic>);
      await pushTv(context, TvMovieDetailScreen(movie: movie));
    } else {
      final series = rawItem is XtreamSeries
          ? rawItem
          : _seriesFromMap(rawItem as Map<String, dynamic>);
      await pushTv(context, TvSeriesDetailScreen(series: series));
    }
    if (mounted) {
      final node = _lastGridFocus;
      if (node != null && node.canRequestFocus) node.requestFocus();
    }
  }

  XtreamSeries _seriesFromMap(Map<String, dynamic> map) => XtreamSeries(
    seriesId:
        map['series_id'] ?? int.tryParse(map['id']?.toString() ?? '0') ?? 0,
    name: map['series_name'] ?? map['name'] ?? map['title'] ?? '',
    cover: map['series_cover'] ?? map['cover'] ?? map['posterUrl'] ?? '',
    categoryId: map['category_id']?.toString() ?? '',
    plot: map['plot'] ?? '',
    cast: map['cast'] ?? '',
    director: map['director'] ?? '',
    genre: map['genre'] ?? '',
    releaseDate: map['releaseDate'] ?? '',
    rating: map['rating']?.toString() ?? '',
    lastModified: int.tryParse(map['last_modified']?.toString() ?? '0') ?? 0,
  );

  /// A stable identity for a tile's Key — see its call site's doc comment.
  /// Falls back to the item's own object identity (still stable across
  /// rebuilds of the same underlying list) for any shape not explicitly
  /// handled, rather than risking a key collision from an empty string.
  Object _idOf(dynamic rawItem) {
    if (rawItem is HistoryItem) return rawItem.id;
    if (rawItem is XtreamVodStream) return rawItem.streamId;
    if (rawItem is XtreamSeries) return rawItem.seriesId;
    if (rawItem is Map<String, dynamic>) {
      return rawItem['stream_id'] ?? rawItem['series_id'] ?? rawItem['id'] ?? rawItem;
    }
    return rawItem;
  }

  String _titleOf(dynamic rawItem) {
    if (rawItem is HistoryItem) return rawItem.title;
    if (rawItem is XtreamVodStream) return rawItem.name;
    if (rawItem is XtreamSeries) return rawItem.name;
    final map = rawItem as Map<String, dynamic>;
    return (map['name'] ?? map['title'] ?? '').toString();
  }

  String _posterOf(dynamic rawItem) {
    if (rawItem is HistoryItem) return rawItem.posterUrl;
    if (rawItem is XtreamVodStream) return rawItem.streamIcon;
    if (rawItem is XtreamSeries) return rawItem.cover;
    final map = rawItem as Map<String, dynamic>;
    return (map['streamIcon'] ?? map['cover'] ?? map['posterUrl'] ?? '')
        .toString();
  }

  bool _isMovieItem(dynamic rawItem) {
    if (rawItem is HistoryItem) return rawItem.type == MediaType.movie;
    return _isMovie;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = widget.title ?? widget.category?.categoryName ?? '';

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
                  TvFocusable(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: colors.ink,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _searchOpen
                        ? TvSearchField(
                            controller: _searchController,
                            hint: 'Search $title',
                            autofocus: true,
                            onChanged: (val) =>
                                setState(() => _searchQuery = val),
                            onClose: () => setState(() {
                              _searchOpen = false;
                              _searchQuery = '';
                              _searchController.clear();
                            }),
                          )
                        : Text(
                            title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: colors.ink,
                              letterSpacing: 1.5,
                            ),
                          ),
                  ),
                  if (!_searchOpen) ...[
                    const SizedBox(width: 16),
                    TvFocusable(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _searchOpen = true),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.search_rounded,
                          color: colors.ink,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Focus(
                  // Observer only — see _lastGridFocus's doc comment.
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: _handleGridFocusChange,
                  child: _buildBody(colors),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppColors colors) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colors.brandPrimary),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!,
              style: GoogleFonts.outfit(
                color: colors.ink.withValues(alpha: 0.54),
              ),
            ),
            const SizedBox(height: 16),
            TvFocusable(
              onTap: _load,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors.brandGradient),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  'Retry',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Client-side filter over the already-loaded category — this is a
    // single category's worth of items (not the whole catalog), so there's
    // nothing to fetch, just narrow what's already here.
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _items
        : _items
              .where((item) => _titleOf(item).toLowerCase().contains(query))
              .toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty ? 'Nothing here yet.' : 'No results found.',
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.38)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = posterGridColumns(constraints.maxWidth);
        final decodeWidth = posterDecodeWidth(constraints.maxWidth, columns);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.65,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final item = filtered[index];
            return TvFocusable(
              // Without a stable, item-derived key, Flutter's Element reuse
              // is purely positional — if `filtered` reorders while a tile
              // is focused (the live search filter above, applied on every
              // keystroke), focus can silently reattach to whatever item
              // now happens to sit at the same index rather than following
              // the item the user was actually on.
              key: ValueKey(_idOf(item)),
              borderRadius: BorderRadius.circular(12),
              autofocus: index == 0,
              onTap: () => _open(item),
              // A permanent soft shadow so posters read as tiles sitting
              // above the background rather than flat cutouts pasted on
              // it — TvFocusable layers its own (bigger, brighter) focus
              // shadow on top of this when the tile is selected.
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _posterOf(item).isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _posterOf(item),
                              fit: BoxFit.cover,
                              memCacheWidth: decodeWidth,
                              errorWidget: (_, _, _) =>
                                  _placeholder(colors, item),
                            )
                          : _placeholder(colors, item),
                      // Bottom scrim + title overlaid directly on the
                      // poster (rather than a separate label below it) —
                      // denser, and keeps every tile's footprint just the
                      // poster's own aspect ratio.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                            child: Text(
                              _titleOf(item),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                height: 1.2,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _placeholder(AppColors colors, dynamic item) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceMuted, colors.surface],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        _isMovieItem(item) ? Icons.movie_rounded : Icons.video_library_rounded,
        color: colors.ink.withValues(alpha: 0.24),
        size: 32,
      ),
    );
  }
}
