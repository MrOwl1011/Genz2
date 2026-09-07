import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import 'series_details_screen.dart';

class SeriesScreen extends StatefulWidget {
  final XtreamCategory? category;
  final List<XtreamSeries>? predefinedList;
  final String? title;

  const SeriesScreen({
    super.key,
    this.category,
    this.predefinedList,
    this.title,
  });

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  List<XtreamSeries> _allSeries = [];
  List<XtreamSeries> _filtered = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (widget.predefinedList != null) {
        if (mounted) {
          setState(() {
            _allSeries = widget.predefinedList!;
            _filtered = widget.predefinedList!;
            _isLoading = false;
          });
        }
        return;
      }

      final content = context.read<ContentProvider>();
      final series = await content.getSeriesList(
        categoryId: widget.category!.categoryId,
      );
      if (mounted) {
        setState(() {
          _allSeries = series;
          _filtered = series;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _onSearch(String query) {
    setState(() {
      _filtered = query.isEmpty
          ? _allSeries
          : _allSeries
                .where(
                  (s) => s.name.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
    });
  }

  void _openSeriesDetails(XtreamSeries series) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SeriesDetailsScreen(series: series)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 24, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: colors.ink,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        (widget.title ?? widget.category?.categoryName ?? '')
                            .toUpperCase(),
                        style: AppType.sans(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: colors.ink,
                          letterSpacing: 1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: colors.border, width: 1.5),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearch,
                    style: AppType.sans(color: colors.ink),
                    decoration: InputDecoration(
                      hintText: isArabic
                          ? 'ابحث عن مسلسلات...'
                          : 'Search series...',
                      hintStyle: AppType.sans(
                        color: colors.ink.withValues(alpha: 0.3),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: colors.ink.withValues(alpha: 0.38),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Content
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final colors = context.colors;
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
        ),
      );
    }

    if (_error != null) {
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
              _error!,
              textAlign: TextAlign.center,
              style: AppType.sans(
                color: colors.ink.withValues(alpha: 0.54),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadSeries,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.brandPrimary,
              ),
              child: Text(
                isArabic ? 'إعادة المحاولة' : 'Retry',
                style: AppType.sans(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد مسلسلات.' : 'No series found.',
          style: AppType.sans(
            color: colors.ink.withValues(alpha: 0.38),
            fontSize: 16,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final series = _filtered[index];
        return GestureDetector(
          onTap: () => _openSeriesDetails(series),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      series.cover.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: series.cover,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(
                                color: colors.surfaceMuted,
                                child: Center(
                                  child: Icon(
                                    Icons.video_library,
                                    color: colors.ink.withValues(alpha: 0.24),
                                    size: 30,
                                  ),
                                ),
                              ),
                              errorWidget: (_, _, _) => Container(
                                color: colors.surfaceMuted,
                                child: Center(
                                  child: Icon(
                                    Icons.video_library,
                                    color: colors.ink.withValues(alpha: 0.24),
                                    size: 30,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: colors.surfaceMuted,
                              child: Center(
                                child: Icon(
                                  Icons.video_library,
                                  color: colors.ink.withValues(alpha: 0.24),
                                  size: 30,
                                ),
                              ),
                            ),
                      // Scrim — fixed regardless of theme, sits directly on
                      // the poster image (see home_screen.dart).
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
                style: AppType.sans(
                  color: colors.ink,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
