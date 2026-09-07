import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../tv_metrics.dart';
import 'tv_focus.dart';

/// One poster in a horizontal content row.
///
/// The title sits *below* the artwork rather than overlaid on it: in a dense
/// row the posters are small enough that an overlaid scrim covers most of the
/// art it's sitting on, and every card ends up looking like a dark rectangle.
/// Below-the-poster keeps the artwork itself clean, which is what makes a row
/// scannable at a glance from across a room.
class TvPosterCard extends StatelessWidget {
  final String title;
  final String posterUrl;
  final VoidCallback onTap;
  final bool autofocus;

  /// Optional line under the title — used for the watch-progress label on
  /// Continue Watching ("Last: S01E01 …").
  final String? subtitle;

  /// 0..1 watch progress, drawn as a bar across the bottom of the artwork.
  /// Null hides it entirely.
  final double? progress;

  final IconData placeholderIcon;

  /// Overrides the self-computed width. The default (screen-width-derived,
  /// see [TvMetrics.posterWidth]) only makes sense when this card sizes
  /// *itself* inside a horizontal [ListView] that hands children unbounded
  /// width — which is every card on the home page. Inside a [GridView]
  /// (e.g. the "More Like This" tab, which shares the screen with another
  /// column and so isn't full-width), the cell size is fixed externally,
  /// and self-computing a different width than the cell it's placed in
  /// causes overflow — so that caller passes its actual cell width here
  /// instead.
  final double? width;

  /// Only ever supplied by a screen restoring a remembered focus position
  /// (see e.g. TvHomeScreen/TvMediaGridScreen) — every ordinary card leaves
  /// this null and lets TvFocusScope create/own its own internal node, same
  /// as before. Not something to pre-allocate per item.
  final FocusNode? focusNode;

  const TvPosterCard({
    super.key,
    required this.title,
    required this.posterUrl,
    required this.onTap,
    this.autofocus = false,
    this.subtitle,
    this.progress,
    this.placeholderIcon = Icons.movie_rounded,
    this.width,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width =
        this.width ?? TvMetrics.posterWidth(MediaQuery.sizeOf(context).width);

    return SizedBox(
      width: width,
      child: TvFocusScope(
        focusNode: focusNode,
        onTap: onTap,
        autofocus: autofocus,
        builder: (context, focused) {
          return AnimatedScale(
            // Scale is a GPU transform — effectively free even on the weak
            // GPUs in budget TV boxes, unlike animating layout or blur.
            scale: focused ? TvMetrics.focusScale : 1,
            duration: TvMetrics.focusAnim,
            curve: Curves.easeOut,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: TvMetrics.posterAspect,
                  child: AnimatedContainer(
                    duration: TvMetrics.focusAnim,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        TvMetrics.posterRadius,
                      ),
                      border: Border.all(
                        // Always a border, transparent when unfocused, so
                        // the card never changes size as focus moves —
                        // a border appearing from nothing would reflow the
                        // whole row.
                        color: focused
                            ? colors.brandAccent
                            : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: focused
                              ? colors.brandAccent.withValues(alpha: 0.55)
                              : Colors.black.withValues(alpha: 0.45),
                          blurRadius: focused ? 20 : 7,
                          spreadRadius: focused ? 1 : 0,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        TvMetrics.posterRadius - 2,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (posterUrl.isEmpty)
                            _placeholder(colors)
                          else
                            CachedNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              // Decode at roughly the size actually drawn
                              // (times a small allowance for the focus
                              // scale) instead of full resolution — dozens
                              // of posters are alive at once in these rows.
                              memCacheWidth: (width * 2.2).round(),
                              placeholder: (_, _) => _placeholder(colors),
                              errorWidget: (_, _, _) => _placeholder(colors),
                            ),
                          if (progress != null && progress! > 0)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: LinearProgressIndicator(
                                value: progress!.clamp(0.0, 1.0),
                                minHeight: 4,
                                backgroundColor: Colors.black54,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colors.brandAccent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  // Two lines rather than one: at eight posters across, a
                  // single line truncated most real titles to a few words.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.archivo(
                    height: 1.15,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: focused ? colors.brandAccent : colors.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.archivo(
                      fontSize: 8.5,
                      color: colors.ink.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _placeholder(AppColors colors) {
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
        placeholderIcon,
        color: colors.ink.withValues(alpha: 0.22),
        size: 22,
      ),
    );
  }
}
