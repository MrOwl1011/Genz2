import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../theme/app_colors.dart';
import '../tv_metrics.dart';
import 'tv_poster_card.dart';

/// The "More Like This" tab: other items from the same category, minus the
/// one already being viewed.
///
/// Xtream has no real recommendation endpoint, so "same category" is the
/// only honest signal available — it's what the category itself already
/// means (these were grouped together on the server), rather than
/// fabricating a similarity score from nothing.
class TvMoreLikeThis extends StatefulWidget {
  final bool isMovie;
  final String categoryId;
  final String excludeId;
  final void Function(XtreamVodStream) onOpenMovie;
  final void Function(XtreamSeries) onOpenSeries;

  const TvMoreLikeThis({
    super.key,
    required this.isMovie,
    required this.categoryId,
    required this.excludeId,
    required this.onOpenMovie,
    required this.onOpenSeries,
  });

  @override
  State<TvMoreLikeThis> createState() => _TvMoreLikeThisState();
}

class _TvMoreLikeThisState extends State<TvMoreLikeThis> {
  List<dynamic> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.categoryId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final content = context.read<ContentProvider>();
      final result = widget.isMovie
          ? await content.getVodStreams(categoryId: widget.categoryId)
          : await content.getSeriesList(categoryId: widget.categoryId);
      if (!mounted) return;
      setState(() {
        _items = result
            .where((item) => _idOf(item) != widget.excludeId)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _idOf(dynamic item) {
    if (item is XtreamVodStream) return item.streamId.toString();
    if (item is XtreamSeries) return item.seriesId.toString();
    return '';
  }

  String _titleOf(dynamic item) {
    if (item is XtreamVodStream) return item.name;
    if (item is XtreamSeries) return item.name;
    return '';
  }

  String _posterOf(dynamic item) {
    if (item is XtreamVodStream) return item.streamIcon;
    if (item is XtreamSeries) return item.cover;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.brandPrimary),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Nothing else in this category yet.',
          style: TextStyle(color: colors.ink.withValues(alpha: 0.4)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // A narrower column than the full-width home rows (this tab shares
        // the screen with the poster/description column beside it), so it
        // targets a smaller poster and gets its own column count rather
        // than reusing TvMetrics.postersPerRow (which assumes the full
        // screen width).
        const targetWidth = 130.0;
        final columns =
            (constraints.maxWidth / (targetWidth + TvMetrics.posterGap))
                .floor()
                .clamp(2, 5);
        final cardWidth =
            (constraints.maxWidth - TvMetrics.posterGap * (columns - 1)) /
            columns;
        final cardHeight = cardWidth / TvMetrics.posterAspect + 40;

        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: TvMetrics.posterGap,
            mainAxisSpacing: TvMetrics.posterGap,
            childAspectRatio: cardWidth / cardHeight,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            return TvPosterCard(
              title: _titleOf(item),
              posterUrl: _posterOf(item),
              width: cardWidth,
              placeholderIcon: widget.isMovie
                  ? Icons.movie_rounded
                  : Icons.video_library_rounded,
              onTap: () {
                if (item is XtreamVodStream) {
                  widget.onOpenMovie(item);
                } else if (item is XtreamSeries) {
                  widget.onOpenSeries(item);
                }
              },
            );
          },
        );
      },
    );
  }
}
