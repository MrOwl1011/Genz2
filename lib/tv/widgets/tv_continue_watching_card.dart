import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_prefs_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../widgets/category_card.dart' show CategoryType;
import '../../widgets/tv_focusable.dart';
import '../screens/tv_media_grid_screen.dart';
import '../tv_route.dart';

/// The wide "Continue Watching" hero on the TV home hub.
///
/// Deliberately not another [TvDestinationTile] — resuming what you were
/// last watching is the single most-used action on a TV IPTV app, so it
/// gets a distinct treatment: the actual poster as a backdrop, the title,
/// and a real progress bar, rather than competing as one more identical
/// square icon tile. Falls back to an inviting empty state (rather than
/// disappearing) so the hub's layout doesn't jump around the first time
/// someone opens the app.
class TvContinueWatchingCard extends StatelessWidget {
  final HistoryItem? item;

  const TvContinueWatchingCard({super.key, this.item});

  // Opens the full watch history rather than resuming this one item
  // directly — lets the user see (and pick from) everything they've been
  // watching, not just the single most-recent item this card shows.
  // TvMediaGridScreen handles the mixed movie/series list fine: each
  // HistoryItem carries its own type (see its _open()).
  void _openHistory(BuildContext context) {
    final userPrefs = context.read<UserPrefsProvider>();
    final isArabic = userPrefs.locale == 'ar';
    pushTv(
      context,
      TvMediaGridScreen(
        type: CategoryType.movie,
        title: isArabic ? 'السجل' : 'History',
        items: userPrefs.history,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = item;

    if (current == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colors.border, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          'Nothing to continue yet — start watching something!',
          style: AppType.sans(color: colors.ink.withValues(alpha: 0.45)),
        ),
      );
    }

    final progress = current.durationMilliseconds > 0
        ? (current.positionMilliseconds / current.durationMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return SizedBox(
      height: 120,
      child: TvFocusable(
        onTap: () => _openHistory(context),
        borderRadius: BorderRadius.circular(4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (current.posterUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: current.posterUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 900,
                )
              else
                Container(color: colors.surfaceMuted),
              // Left-to-right scrim so the poster stays visible on the
              // right while the text on the left is always readable,
              // regardless of the artwork's own colours.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        colors.background.withValues(alpha: 0.96),
                        colors.background.withValues(alpha: 0.75),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.play_circle_fill_rounded,
                          color: colors.ink,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'CONTINUE WATCHING',
                          style: AppType.sans(
                            color: colors.ink,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Text(
                        current.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          minHeight: 5,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.ink),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
