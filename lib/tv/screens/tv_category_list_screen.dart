import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/user_prefs_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/category_card.dart' show CategoryType;
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_search_field.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import 'tv_media_grid_screen.dart';

/// TV-native replacement for [MoviesCategoryScreen]/[SeriesCategoryScreen] —
/// not the phone screen patched with focus support, but built for a remote
/// from the start: a dense 2-column category list (no per-category network
/// fetch just to render a thumbnail — see the icon-avatar note below), the
/// same All/Liked/New/History tabs the phone version has, and posters sized
/// for the room-viewing-distance TV grids use everywhere else in this app.
class TvCategoryListScreen extends StatefulWidget {
  final CategoryType type;

  const TvCategoryListScreen({super.key, required this.type});

  @override
  State<TvCategoryListScreen> createState() => _TvCategoryListScreenState();
}

class _TvCategoryListScreenState extends State<TvCategoryListScreen> {
  int _selectedTab = 0;
  bool _searchOpen = false;
  final _searchController = TextEditingController();

  bool get _isMovie => widget.type == CategoryType.movie;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCategory(XtreamCategory category) {
    pushTv(context, TvMediaGridScreen(type: widget.type, category: category));
  }

  void _openList(String title, List<dynamic> items) {
    pushTv(
      context,
      TvMediaGridScreen(type: widget.type, title: title, items: items),
    );
  }

  // Cross-category — unlike the in-category search on TvMediaGridScreen,
  // there's no already-loaded list to filter here, so this needs a real
  // query against the whole catalog (ContentProvider.searchAll), fired
  // once on submit rather than per-keystroke.
  void _submitSearch(String query, ContentProvider content, bool isArabic) {
    if (query.trim().isEmpty) return;
    final results = content.searchAll(query);
    final items = _isMovie ? results.movies : results.series;
    setState(() => _searchOpen = false);
    _openList(
      isArabic ? 'نتائج البحث عن "$query"' : 'Results for "$query"',
      items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = context.watch<ContentProvider>();
    final userPrefs = context.watch<UserPrefsProvider>();
    final isArabic = userPrefs.locale == 'ar';

    final categories = _isMovie
        ? content.vodCategories
        : content.seriesCategories;
    final isLoading = _isMovie ? content.isLoadingVod : content.isLoadingSeries;
    final error = _isMovie ? content.vodError : content.seriesError;
    final title = _isMovie
        ? (isArabic ? 'أفلام' : 'MOVIES')
        : (isArabic ? 'مسلسلات' : 'SERIES');

    final tabs = isArabic
        ? const ['الكل', 'المفضلة', 'جديد', 'السجل']
        : const ['All', 'Liked', 'New', 'History'];

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
                  const SizedBox(width: 12),
                  _searchOpen
                      ? Expanded(
                          child: TvSearchField(
                            controller: _searchController,
                            hint: isArabic
                                ? 'ابحث في كل $title'
                                : 'Search all $title',
                            autofocus: true,
                            onChanged: (_) {},
                            onSubmit: (query) =>
                                _submitSearch(query, content, isArabic),
                            onClose: () {
                              setState(() => _searchOpen = false);
                              _searchController.clear();
                            },
                          ),
                        )
                      : Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: colors.ink,
                            letterSpacing: 1.5,
                          ),
                        ),
                  if (!_searchOpen) const Spacer(),
                  const SizedBox(width: 12),
                  if (!_searchOpen) ...[
                    TvFocusable(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        content.loadAllContent();
                        setState(() => _searchOpen = true);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          color: colors.ink.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  TvFocusable(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _isMovie
                        ? content.loadVodCategories()
                        : content.loadSeriesCategories(),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.refresh_rounded,
                        color: colors.ink.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  for (final (i, label) in tabs.indexed) ...[
                    _TvTab(
                      label: label,
                      selected: _selectedTab == i,
                      onTap: () => setState(() => _selectedTab = i),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _buildBody(
                  colors,
                  isArabic,
                  content,
                  userPrefs,
                  categories,
                  isLoading,
                  error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    AppColors colors,
    bool isArabic,
    ContentProvider content,
    UserPrefsProvider userPrefs,
    List<XtreamCategory> categories,
    bool isLoading,
    String? error,
  ) {
    if (_selectedTab == 1) {
      final targetType = _isMovie ? MediaType.movie : MediaType.series;
      final items = userPrefs.favorites
          .where((f) => f.type == targetType)
          .map((f) => f.rawData)
          .toList();
      return _buildGridPreview(
        colors,
        isArabic,
        items,
        empty: isArabic ? 'لا توجد عناصر في المفضلة.' : 'Nothing liked yet.',
      );
    }
    if (_selectedTab == 2) {
      final items = _isMovie ? content.newMovies : content.newSeries;
      return _buildGridPreview(
        colors,
        isArabic,
        items,
        empty: isArabic ? 'لا يوجد جديد حالياً.' : 'Nothing new right now.',
      );
    }
    if (_selectedTab == 3) {
      final targetType = _isMovie ? MediaType.movie : MediaType.series;
      final items = userPrefs.history
          .where((h) => h.type == targetType)
          .map((h) => h.rawData)
          .toList();
      return _buildGridPreview(
        colors,
        isArabic,
        items,
        empty: isArabic ? 'لا يوجد سجل مشاهدة.' : 'No watch history yet.',
      );
    }

    if (isLoading && categories.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: colors.brandPrimary),
      );
    }
    if (error != null && categories.isEmpty) {
      return Center(
        child: Text(
          error,
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.54)),
        ),
      );
    }
    if (categories.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد فئات.' : 'No categories found.',
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.38)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Dense 2-up (or more, on a wider panel) list rather than the
        // phone's single full-width column — see the reference layout this
        // was modeled on: a category is just a name, it doesn't need a
        // whole poster-sized row to itself.
        final columns = (constraints.maxWidth / 420).round().clamp(2, 4);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 4.2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return _TvCategoryRow(
              category: category,
              type: widget.type,
              autofocus: index == 0,
              onTap: () => _openCategory(category),
            );
          },
        );
      },
    );
  }

  Widget _buildGridPreview(
    AppColors colors,
    bool isArabic,
    List<dynamic> items, {
    required String empty,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          empty,
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.38)),
        ),
      );
    }
    final label = _selectedTab == 1
        ? (isArabic ? 'المفضلة' : 'Liked')
        : _selectedTab == 2
        ? (isArabic ? 'جديد' : 'New')
        : (isArabic ? 'السجل' : 'History');
    // Straight into the grid screen rather than re-implementing the grid
    // here too — the tab's whole job is just picking which item list feeds
    // the same TV-native poster grid every other browsing path already uses.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openList(label, items);
    });
    return const SizedBox.shrink();
  }
}

class _TvTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TvTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TvFocusable(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? LinearGradient(colors: colors.brandGradient)
              : null,
          color: selected ? null : colors.surface.withValues(alpha: 0.5),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: selected ? Colors.white : colors.ink.withValues(alpha: 0.7),
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _TvCategoryRow extends StatelessWidget {
  final XtreamCategory category;
  final CategoryType type;
  final bool autofocus;
  final VoidCallback onTap;

  const _TvCategoryRow({
    required this.category,
    required this.type,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Deliberately no per-category thumbnail fetch here (the phone version's
    // CategoryCard fetches that category's entire stream list just to read
    // the first item's icon off it) — fine for a handful of rows, but this
    // screen can show dozens of categories at once, and firing that many
    // extra full-list network requests just to decorate a list is exactly
    // the kind of thing that made browsing feel slow. A themed icon costs
    // nothing and is still perfectly legible from a couch.
    final icon = type == CategoryType.movie
        ? Icons.movie_rounded
        : Icons.video_library_rounded;
    return TvFocusable(
      borderRadius: BorderRadius.circular(14),
      autofocus: autofocus,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.brandPrimary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colors.brandAccent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                category.categoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: colors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
