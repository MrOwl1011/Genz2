import 'package:flutter/material.dart';

import '../../core/build_flavor.dart' show kIsTvRemote;
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../tv_metrics.dart';
import 'tv_focus.dart';

/// A titled horizontal strip of posters — the core unit of the home page.
///
/// Scrolling is driven entirely by focus: Flutter's directional traversal
/// calls `Scrollable.ensureVisible` on whatever it moves focus to, which
/// scrolls this row to reveal that card. That's why the row can — and
/// should — refuse user scroll physics below: there's no touch to fling it
/// with on a TV, and an independently scrollable viewport would just drift
/// out of sync with where focus actually is. Programmatic `ensureVisible`
/// still works under `NeverScrollableScrollPhysics`, since physics only
/// governs user input, not scrolls the framework drives itself.
class TvContentRow extends StatefulWidget {
  final String title;

  /// Tapping the in-row "See all" tile (the 11th slot, once the row is
  /// capped) opens the full grid. Omitted for rows that are already
  /// complete (Continue Watching, once it has 10 or fewer items).
  final VoidCallback? onSeeAll;

  final List<Widget> children;
  final bool isArabic;

  const TvContentRow({
    super.key,
    required this.title,
    required this.children,
    required this.isArabic,
    this.onSeeAll,
  });

  @override
  State<TvContentRow> createState() => _TvContentRowState();
}

/// A row only ever shows this many posters before handing off to the "See
/// all" tile — keeps every row a quick, glanceable strip instead of a long
/// scroll-to-find-it list. One less than [TvMetrics.postersPerRow], so the
/// posters plus the tile fill the row exactly and the tile never needs a
/// scroll to reach.
const int _kRowDisplayCap = 8;

class _TvContentRowState extends State<TvContentRow> {
  final _scroll = ScrollController();
  bool _rowHasFocus = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rowHeight = TvMetrics.rowHeight(MediaQuery.sizeOf(context).width);

    return Focus(
      // Not focusable itself — purely an observer for "is the D-pad
      // somewhere inside this row right now", so the row's own title can
      // answer "which category am I in" at a glance without the user
      // having to track it card-by-card, the same way TvSidebar's own
      // observer Focus drives its expand state.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        // See TvFocusable's identical reasoning: this exists to answer
        // "which category am I in" for a D-pad user, which is meaningless
        // without one — suppressed on iPad, harmless no-op on plain phone
        // (kIsTvRemote is always false there too, but this widget is
        // TV-exclusive so that case never actually renders it).
        final reported = hasFocus && kIsTvRemote;
        if (reported != _rowHasFocus) setState(() => _rowHasFocus = reported);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AnimatedDefaultTextStyle(
              duration: TvMetrics.focusAnim,
              style: AppType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: _rowHasFocus ? colors.ink : colors.ink,
                letterSpacing: 1.2,
              ),
              child: Text(
                widget.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(
            height: rowHeight,
            child: FocusTraversalGroup(
              child: Builder(
                builder: (context) {
                  final overflowing = widget.children.length > _kRowDisplayCap;
                  final showSeeAllTile = overflowing && widget.onSeeAll != null;
                  final visible = overflowing
                      ? widget.children.take(_kRowDisplayCap).toList()
                      : widget.children;
                  final itemCount = visible.length + (showSeeAllTile ? 1 : 0);

                  return ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    // A remote can't fling this, and letting it scroll
                    // physically would let the viewport drift out of sync
                    // with where focus actually is.
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: itemCount,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: TvMetrics.posterGap),
                    itemBuilder: (context, index) {
                      if (index < visible.length) return visible[index];
                      return _SeeAllTile(
                        onTap: widget.onSeeAll!,
                        isArabic: widget.isArabic,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tile that ends a row once it's been capped at [_kRowDisplayCap]
/// items — takes the same *slot width* as [TvPosterCard] so 11 things
/// (10 posters + this) line up evenly across the row, but is deliberately
/// not another poster-sized card: a small centered circular button reads
/// as an action, not as competing artwork.
class _SeeAllTile extends StatelessWidget {
  final VoidCallback onTap;
  final bool isArabic;

  const _SeeAllTile({required this.onTap, required this.isArabic});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width = TvMetrics.posterWidth(MediaQuery.sizeOf(context).width);
    final circleSize = (width * 0.5).clamp(34.0, 56.0);

    return SizedBox(
      width: width,
      child: TvFocusScope(
        onTap: onTap,
        builder: (context, focused) {
          return AspectRatio(
            aspectRatio: TvMetrics.posterAspect,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: focused ? TvMetrics.focusScale : 1,
                    duration: TvMetrics.focusAnim,
                    curve: Curves.easeOut,
                    child: AnimatedContainer(
                      duration: TvMetrics.focusAnim,
                      width: circleSize,
                      height: circleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: focused
                            ? LinearGradient(colors: colors.brandGradient)
                            : null,
                        color: focused ? null : colors.surface,
                        border: Border.all(
                          color: focused ? Colors.transparent : colors.border,
                          width: 1.5,
                        ),
                        boxShadow: focused
                            ? [
                                BoxShadow(
                                  color: colors.brandPrimary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: focused ? Colors.white : colors.ink,
                        size: circleSize * 0.42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isArabic ? 'عرض الكل' : 'See All',
                    textAlign: TextAlign.center,
                    style: AppType.sans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: focused
                          ? colors.ink
                          : colors.ink.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
