import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/download_item.dart';
import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/downloads_provider.dart';
import '../../providers/user_prefs_provider.dart';
import '../../screens/player_screen.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../widgets/resume_dialog.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import '../widgets/tv_detail_action_button.dart';
import '../widgets/tv_focus.dart';

/// TV-native movie detail screen: a small poster beside its title,
/// metadata, description and action buttons, over a blurred backdrop —
/// matching the same design language as the TV home page.
///
/// Deliberately just this one block, nothing below it: this app has no
/// per-title recommendation data or cast/crew photos to fill a second
/// section with (see the git history for the tabbed More-Like-This/Cast
/// layout this replaced, if that ever becomes available).
class TvMovieDetailScreen extends StatefulWidget {
  final XtreamVodStream movie;

  const TvMovieDetailScreen({super.key, required this.movie});

  @override
  State<TvMovieDetailScreen> createState() => _TvMovieDetailScreenState();
}

class _TvMovieDetailScreenState extends State<TvMovieDetailScreen> {
  XtreamVodInfo? _vodInfo;
  bool _isLoading = true;
  // Ids currently awaiting DownloadsProvider.pauseDownload's server-support
  // check — see the matching field in movie_details_screen.dart for why
  // this needs its own flag rather than just reading item.status.
  final Set<String> _pausingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = context.read<ContentProvider>();
      final info = await content.getVodInfo(widget.movie.streamId);
      if (mounted) setState(() => _vodInfo = info);
    } catch (_) {
      // Non-fatal — falls back to widget.movie's own fields below.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openPlayer({bool offline = false}) async {
    final content = context.read<ContentProvider>();
    final userPrefs = context.read<UserPrefsProvider>();
    final mediaId = widget.movie.streamId.toString();
    // Prefer the freshly-fetched info over the list-row snapshot passed in —
    // see the identical comment in movie_details_screen.dart's _openPlayer.
    final currentMovie = _vodInfo?.movieData ?? widget.movie;

    String url;
    if (offline) {
      final filePath = context
          .read<DownloadsProvider>()
          .itemFor(mediaId)
          ?.filePath;
      if (filePath == null) return;
      url = Uri.file(filePath).toString();
    } else {
      url = currentMovie.streamUrl(
        content.baseUrl,
        content.username,
        content.password,
      );
    }

    int position = userPrefs.getHistoryPosition(mediaId);
    if (position > 30) {
      final result = await showResumeDialog(context, position);
      if (!mounted) return;
      if (result == null) return;
      if (result == false) {
        position = 0;
        userPrefs.clearHistoryPosition(mediaId);
      }
    }

    if (!mounted) return;
    pushTv(
      context,
      PlayerScreen(
        streamUrl: url,
        title: currentMovie.name,
        coverUrl: currentMovie.streamIcon,
        isLive: false,
        mediaId: mediaId,
        mediaType: MediaType.movie,
        rawMediaData: currentMovie.toJson(),
        initialPositionSeconds: position,
      ),
    );
  }

  Future<void> _pause(DownloadsProvider downloads, String mediaId) async {
    setState(() => _pausingIds.add(mediaId));
    try {
      await downloads.pauseDownload(mediaId);
    } finally {
      if (mounted) setState(() => _pausingIds.remove(mediaId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = _vodInfo?.movieData.name ?? widget.movie.name;
    final cover = _vodInfo?.movieData.streamIcon ?? widget.movie.streamIcon;
    final plot = _vodInfo?.movieData.plot ?? widget.movie.plot;
    final genre = _vodInfo?.movieData.genre ?? widget.movie.genre;
    final releaseDate =
        _vodInfo?.movieData.releaseDate ?? widget.movie.releaseDate;
    final duration = _vodInfo?.duration ?? '';
    final year = releaseDate.length >= 4
        ? releaseDate.substring(0, 4)
        : releaseDate;

    final userPrefs = context.watch<UserPrefsProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final content = context.read<ContentProvider>();
    final mediaId = widget.movie.streamId.toString();
    final isFav = userPrefs.isFavorite(mediaId);
    final sourceUrl = (_vodInfo?.movieData ?? widget.movie).streamUrl(
      content.baseUrl,
      content.username,
      content.password,
    );
    final canDownload =
        downloads.isDownloaded(mediaId) ||
        downloads.isDownloading(mediaId) ||
        DownloadsProvider.isDownloadable(sourceUrl);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Deliberately NOT wrapped in ImageFiltered/ImageFilter.blur any
          // more. A full-screen 30-sigma blur is one of the most expensive
          // things you can ask a GPU to do every frame, and the budget GPUs
          // in TV boxes handle it far worse than a phone — it was a prime
          // suspect for this screen hanging on its loading spinner and then
          // dying on real TV hardware. It also bought very little: the image
          // is decoded at memCacheWidth 320 and then stretched across a
          // 1080p+ panel, so it is already heavily softened by upscaling
          // alone, and the dark scrim below does the rest of the work of
          // keeping the foreground text readable.
          if (cover.isNotEmpty)
            CachedNetworkImage(
              imageUrl: cover,
              fit: BoxFit.cover,
              memCacheWidth: 320,
              errorWidget: (_, _, _) => Container(color: colors.surfaceMuted),
            )
          else
            Container(color: colors.surfaceMuted),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.withValues(alpha: 0.72),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: TvMetrics.safeArea.horizontal / 2,
                vertical: TvMetrics.safeArea.vertical / 2,
              ),
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colors.brandPrimary,
                      ),
                    )
                  // Poster on the left, everything else beside it rather
                  // than underneath — a small poster with a full column of
                  // text below it left most of the screen empty; putting
                  // the text alongside instead actually uses that space.
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            // A quarter of the previous 380px column — see
                            // the class doc comment for why there's no
                            // second section competing for space anymore.
                            width: 95,
                            child: AspectRatio(
                              aspectRatio: TvMetrics.posterAspect,
                              child: cover.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: cover,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 210,
                                    )
                                  : Container(color: colors.surfaceMuted),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title.toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.sans(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (year.isNotEmpty)
                                    Text(
                                      year,
                                      style: AppType.caption(
                                        colors.ink.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  if (duration.isNotEmpty)
                                    Text(
                                      duration,
                                      style: AppType.caption(
                                        colors.ink.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  if (genre.isNotEmpty)
                                    // NOT Flexible: this is a Wrap child, and
                                    // Flexible only works inside a Flex
                                    // (Row/Column). Putting one here threw
                                    // "type 'WrapParentData' is not a subtype of
                                    // type 'FlexParentData'" at build time, which
                                    // then re-threw every rebuild — pinning the
                                    // main thread and taking the whole app down
                                    // with an ANR. It only reproduced on titles
                                    // that actually carry a genre string, which
                                    // is why it looked intermittent. A plain
                                    // width cap gives the same "don't let a long
                                    // genre run off the line" behaviour that was
                                    // wanted here.
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 280,
                                      ),
                                      child: Text(
                                        genre,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppType.caption(
                                          colors.ink.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (plot.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  plot,
                                  // More width to work with here than the
                                  // old narrow left column had, so a couple
                                  // more lines fit before truncating.
                                  maxLines: 8,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.body(
                                    colors.ink.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  TvDetailActionButton(
                                    primary: true,
                                    autofocus: true,
                                    icon: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                    onTap: () => _openPlayer(),
                                  ),
                                  const SizedBox(width: 14),
                                  TvDetailActionButton(
                                    icon: Icon(
                                      isFav
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: isFav
                                          ? colors.brandPrimary
                                          : Colors.black,
                                      size: 22,
                                    ),
                                    onTap: () => userPrefs.toggleFavorite(
                                      id: mediaId,
                                      title: widget.movie.name,
                                      posterUrl: widget.movie.streamIcon,
                                      type: MediaType.movie,
                                      rawData: widget.movie.toJson(),
                                    ),
                                  ),
                                  if (canDownload) ...[
                                    const SizedBox(width: 14),
                                    TvDetailActionButton(
                                      icon: _downloadIcon(
                                        downloads,
                                        mediaId,
                                        colors,
                                      ),
                                      onTap: () => _handleDownloadTap(
                                        downloads,
                                        mediaId,
                                        sourceUrl,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          Positioned(
            top: TvMetrics.safeArea.vertical / 2,
            right: TvMetrics.safeArea.horizontal / 2,
            child: TvFocusScope(
              onTap: () => Navigator.of(context).pop(),
              builder: (context, focused) => Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: focused
                      ? colors.brandPrimary
                      : Colors.black.withValues(alpha: 0.5),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _downloadIcon(
    DownloadsProvider downloads,
    String mediaId,
    AppColors colors,
  ) {
    if (downloads.isDownloaded(mediaId)) {
      return const Icon(
        Icons.play_circle_fill_rounded,
        color: Colors.black,
        size: 22,
      );
    }
    if (downloads.isDownloading(mediaId)) {
      // itemFor should always find an entry when isDownloading is true (both
      // read the same list), but this is a build() path — falling back to
      // the plain download icon on any inconsistency is far cheaper than a
      // null-check crash taking down the whole screen.
      final item = downloads.itemFor(mediaId);
      if (item == null) {
        return const Icon(
          Icons.download_rounded,
          color: Colors.black,
          size: 22,
        );
      }
      final isPaused = item.status == DownloadStatus.paused;
      final isPausing = _pausingIds.contains(mediaId);
      if (isPaused) {
        return const Icon(
          Icons.play_arrow_rounded,
          color: Colors.black,
          size: 22,
        );
      }
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          value: !isPausing && item.totalBytes > 0 ? item.progress : null,
          valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
        ),
      );
    }
    return const Icon(Icons.download_rounded, color: Colors.black, size: 22);
  }

  void _handleDownloadTap(
    DownloadsProvider downloads,
    String mediaId,
    String sourceUrl,
  ) {
    if (downloads.isDownloaded(mediaId)) {
      _openPlayer(offline: true);
      return;
    }
    if (downloads.isDownloading(mediaId)) {
      final item = downloads.itemFor(mediaId);
      if (item == null) return;
      final isPaused = item.status == DownloadStatus.paused;
      if (!DownloadsProvider.pauseSupported) {
        downloads.cancelDownload(mediaId);
      } else if (isPaused) {
        downloads.resumeDownload(mediaId);
      } else if (!_pausingIds.contains(mediaId)) {
        _pause(downloads, mediaId);
      }
      return;
    }
    downloads.startDownload(
      id: mediaId,
      title: widget.movie.name,
      posterUrl: widget.movie.streamIcon,
      type: MediaType.movie,
      sourceUrl: sourceUrl,
      rawData: widget.movie.toJson(),
    );
  }
}
