import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../theme/app_colors.dart';
import 'tv_focusable.dart';

enum CategoryType { live, movie, series }

class CategoryCard extends StatefulWidget {
  final XtreamCategory category;
  final CategoryType type;
  final VoidCallback onTap;

  const CategoryCard({
    super.key,
    required this.category,
    required this.type,
    required this.onTap,
  });

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  String? _coverUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCover();
  }

  Future<void> _fetchCover() async {
    try {
      final content = context.read<ContentProvider>();

      if (widget.type == CategoryType.movie) {
        final streams = await content.getVodStreams(
          categoryId: widget.category.categoryId,
        );
        if (streams.isNotEmpty && mounted) {
          setState(() {
            _coverUrl = streams.first.streamIcon;
            _isLoading = false;
          });
          return;
        }
      } else if (widget.type == CategoryType.series) {
        final series = await content.getSeriesList(
          categoryId: widget.category.categoryId,
        );
        if (series.isNotEmpty && mounted) {
          setState(() {
            _coverUrl = series.first.cover;
            _isLoading = false;
          });
          return;
        }
      } else if (widget.type == CategoryType.live) {
        final streams = await content.getLiveStreams(
          categoryId: widget.category.categoryId,
        );
        if (streams.isNotEmpty && mounted) {
          setState(() {
            _coverUrl = streams.first.streamIcon;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      // Ignore errors for cover fetch, just show placeholder
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TvFocusable(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colors.surfaceMuted, // Neutral card background
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Left Side: Image
            SizedBox(
              width: 100,
              height: 100,
              child: _isLoading
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors.brandPrimary,
                          ),
                        ),
                      ),
                    )
                  : (_coverUrl != null && _coverUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: _coverUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
            ),

            // Right Side: Text
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.category.categoryName,
                      style: GoogleFonts.archivo(
                        color: colors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildPlaceholder() {
    final colors = context.colors;
    IconData icon;
    switch (widget.type) {
      case CategoryType.movie:
        icon = Icons.movie;
        break;
      case CategoryType.series:
        icon = Icons.video_library;
        break;
      case CategoryType.live:
        icon = Icons.live_tv;
        break;
    }
    return Container(
      color: colors.surfaceMuted,
      child: Icon(icon, color: colors.ink.withValues(alpha: 0.24), size: 30),
    );
  }
}
