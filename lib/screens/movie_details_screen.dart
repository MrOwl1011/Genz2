import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../core/build_flavor.dart' show kIsTv;
import '../models/download_item.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_dialog.dart';
import 'player_screen.dart';

class MovieDetailsScreen extends StatefulWidget {
  final XtreamVodStream movie;

  const MovieDetailsScreen({super.key, required this.movie});

  @override
  State<MovieDetailsScreen> createState() => _MovieDetailsScreenState();
}

class _MovieDetailsScreenState extends State<MovieDetailsScreen> {
  XtreamVodInfo? _vodInfo;
  bool _isLoading = true;
  // Ids currently awaiting DownloadsProvider.pauseDownload's server-support
  // check — that can take several seconds (see the comment there), so the
  // pause button shows a spinner instead of looking frozen/unresponsive.
  final Set<String> _pausingIds = {};

  @override
  void initState() {
    super.initState();
    _loadVodInfo();
  }

  Future<void> _loadVodInfo() async {
    try {
      final content = context.read<ContentProvider>();
      final info = await content.getVodInfo(widget.movie.streamId);
      if (mounted) {
        setState(() {
          _vodInfo = info;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Opens the player with resume dialog support.
  /// Shows a dialog if saved position > 30 seconds. Pass [offline] to play
  /// back the downloaded local copy instead of streaming from the server.
  void _openPlayer(BuildContext context, {bool offline = false}) async {
    final content = context.read<ContentProvider>();
    final userPrefs = context.read<UserPrefsProvider>();
    final mediaId = widget.movie.streamId.toString();

    // Prefer the freshly-fetched _vodInfo (see _loadVodInfo) over
    // widget.movie for building the stream URL/raw data. widget.movie can
    // be a frozen snapshot reconstructed from History/Favorites rawData —
    // possibly saved long ago — so its direct_source can point at content
    // that's since moved or changed even though the server now serves
    // something different for this same stream_id. Falls back to
    // widget.movie only if the live re-fetch hasn't completed/failed.
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

    // Show resume dialog if position > 30 seconds
    if (position > 30) {
      final result = await showResumeDialog(context, position);
      if (!mounted) return;
      if (result == null) {
        return; // dismissed via X or outside tap — cancelled, don't open the player
      }
      if (result == false) {
        position = 0; // User chose "Start Over"
        userPrefs.clearHistoryPosition(widget.movie.streamId.toString());
      }
      // result == true means resume from saved position
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              streamUrl: url,
              title: currentMovie.name,
              coverUrl: currentMovie.streamIcon,
              isLive: false,
              mediaId: widget.movie.streamId.toString(),
              mediaType: MediaType.movie,
              rawMediaData: currentMovie.toJson(),
              initialPositionSeconds: position,
            ),
          ),
        )
        .then((_) {
          // Refresh UI in case history was updated
          setState(() {});
        });
  }

  @override
  Widget build(BuildContext context) {
    // Determine the text to show (prefer full info from getVodInfo if available)
    final title = _vodInfo?.movieData.name ?? widget.movie.name;
    final cover = _vodInfo?.movieData.streamIcon ?? widget.movie.streamIcon;
    final plot = _vodInfo?.movieData.plot ?? widget.movie.plot;
    final cast = _vodInfo?.movieData.cast ?? widget.movie.cast;
    final director = _vodInfo?.movieData.director ?? widget.movie.director;
    final genre = _vodInfo?.movieData.genre ?? widget.movie.genre;
    final releaseDate =
        _vodInfo?.movieData.releaseDate ?? widget.movie.releaseDate;
    final duration = _vodInfo?.duration ?? '';

    final userPrefs = context.watch<UserPrefsProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final mediaId = widget.movie.streamId.toString();
    final isFav = userPrefs.isFavorite(mediaId);
    final isArabic = userPrefs.locale == 'ar';
    final colors = context.colors;
    final content = context.read<ContentProvider>();
    // See the matching comment in _openPlayer — prefer the freshly-fetched
    // _vodInfo over widget.movie, which can be a frozen History/Favorites
    // snapshot with a stale source URL.
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
      backgroundColor: colors.background,
      body: Stack(
        children: [
          // Background Poster
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // TV: a landscape screen needs much less vertical hero space and
            // much more room for the details card below (see the matching
            // height on that card) — the phone's near-even 55/55 split badly
            // cramped the description/episode list on TV, cutting the
            // description off with no way to tell more was below the fold.
            height: MediaQuery.of(context).size.height * (kIsTv ? 0.32 : 0.55),
            child: Stack(
              fit: StackFit.expand,
              children: [
                cover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: cover,
                        fit: BoxFit.cover,
                        errorWidget: (context, error, stackTrace) =>
                            Container(color: colors.surfaceMuted),
                      )
                    : Container(color: colors.surfaceMuted),
                // Gradient to blend poster into background — tracks the
                // theme's background color so the blend stays seamless.
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        colors.background.withValues(alpha: 0.53),
                        colors.background,
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 28,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Draggable/Scrollable Details Card
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              // TV: much taller than the backdrop above gives back — see
              // that height's comment. Most of the screen on TV, since
              // there's no touch-scroll affordance to hint more content is
              // below the fold the way a phone's drag handle implies.
              height:
                  MediaQuery.of(context).size.height * (kIsTv ? 0.78 : 0.55),
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Play Button (Overlapping top edge)
                  Positioned(
                    top: -36,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                color: isFav
                                    ? colors.brandPrimary
                                    : Colors.black,
                              ),
                              focusColor: colors.brandAccent.withValues(
                                alpha: 0.35,
                              ),
                              onPressed: () {
                                // Provide toJson method in XtreamVodStream
                                userPrefs.toggleFavorite(
                                  id: widget.movie.streamId.toString(),
                                  title: widget.movie.name,
                                  posterUrl: widget.movie.streamIcon,
                                  type: MediaType.movie,
                                  rawData: {
                                    'stream_id': widget.movie.streamId,
                                    'name': widget.movie.name,
                                    'stream_icon': widget.movie.streamIcon,
                                    'category_id': widget.movie.categoryId,
                                    'container_extension':
                                        widget.movie.containerExtension,
                                    'plot': widget.movie.plot,
                                    'cast': widget.movie.cast,
                                    'director': widget.movie.director,
                                    'genre': widget.movie.genre,
                                    'releaseDate': widget.movie.releaseDate,
                                    'rating': widget.movie.rating,
                                    'added': widget.movie.added,
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Material+InkWell rather than a bare GestureDetector:
                          // a GestureDetector deferring hit-testing to a
                          // BoxShape.circle child only accepts taps inside the
                          // inscribed circle, missing the corners of this
                          // 72x72 box — that's what made the button feel like
                          // it "sometimes" needed several taps. InkWell hit-
                          // tests its full rectangular bounds regardless of
                          // customBorder, so every tap in the square lands,
                          // and it gives a visible ripple to confirm it did.
                          Material(
                            color: colors.brandPrimary,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              focusColor: Colors.white.withValues(alpha: 0.35),
                              // TV: this screen's back button sits top-left
                              // while this row sits centered lower down, with
                              // no horizontal overlap — Flutter's directional
                              // focus can't bridge between them, so DOWN from
                              // back finds no candidate and focus gets stuck
                              // there, making select trigger "back" instead
                              // of play. Autofocusing Play on open sidesteps
                              // that entirely and matches how real TV apps
                              // land focus on the primary action by default.
                              autofocus: kIsTv,
                              onTap: () => _openPlayer(context),
                              child: const SizedBox(
                                width: 72,
                                height: 72,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                          if (canDownload) ...[
                            const SizedBox(width: 16),
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: _buildDownloadButton(
                                context,
                                downloads,
                                mediaId,
                                sourceUrl,
                                colors,
                                isArabic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Content List
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                    child: _isLoading
                        ? Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colors.brandPrimary,
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Thumbnail
                                    Container(
                                      width: kIsTv ? 76 : 100,
                                      height: kIsTv ? 114 : 150,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        image: DecorationImage(
                                          image: CachedNetworkImageProvider(
                                            cover,
                                          ),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title.toUpperCase(),
                                            style: GoogleFonts.archivo(
                                              fontSize: kIsTv ? 19 : 24,
                                              fontWeight: FontWeight.w900,
                                              fontStyle: FontStyle.italic,
                                              color: colors.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (releaseDate.isNotEmpty)
                                            Text(
                                              releaseDate,
                                              style: GoogleFonts.archivo(
                                                color: colors.ink.withValues(
                                                  alpha: 0.7,
                                                ),
                                              ),
                                            ),
                                          if (duration.isNotEmpty)
                                            Text(
                                              duration,
                                              style: GoogleFonts.archivo(
                                                color: colors.ink.withValues(
                                                  alpha: 0.7,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: kIsTv ? 10 : 16),
                                if (genre.isNotEmpty)
                                  Text(
                                    genre,
                                    style: GoogleFonts.archivo(
                                      color: colors.ink,
                                      fontWeight: FontWeight.bold,
                                      fontSize: kIsTv ? 14 : 16,
                                    ),
                                  ),
                                SizedBox(height: kIsTv ? 8 : 12),
                                // TV: capped rather than left to run on —
                                // there's no scroll-hint affordance like a
                                // phone's drag handle, so a description that
                                // just trails off the bottom of the screen
                                // reads as broken/cut-off rather than
                                // "scroll for more". A fixed line count plus
                                // ellipsis always reads as complete.
                                if (plot.isNotEmpty)
                                  Text(
                                    plot,
                                    maxLines: kIsTv ? 4 : null,
                                    overflow: kIsTv
                                        ? TextOverflow.ellipsis
                                        : TextOverflow.clip,
                                    style: GoogleFonts.archivo(
                                      color: colors
                                          .brandPrimary, // Brand-colored description per user request
                                      fontSize: kIsTv ? 13 : 15,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.justify,
                                  ),
                                const SizedBox(height: 16),
                                if (cast.isNotEmpty) ...[
                                  Text(
                                    cast,
                                    style: GoogleFonts.archivo(
                                      color: colors.ink.withValues(alpha: 0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (director.isNotEmpty) ...[
                                  Text(
                                    director,
                                    style: GoogleFonts.archivo(
                                      color: colors.ink.withValues(alpha: 0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pauses a download, surfacing the case where the server doesn't support
  /// resumable downloads — pausing there can't be resumed later, so it's
  /// left running instead of being torn down; see
  /// [DownloadsProvider.pauseDownload].
  Future<void> _pause(
    BuildContext context,
    DownloadsProvider downloads,
    String id,
  ) async {
    setState(() => _pausingIds.add(id));
    final paused = await downloads.pauseDownload(id);
    if (!mounted) return;
    setState(() => _pausingIds.remove(id));
    if (!paused && context.mounted) {
      final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'لا يمكن إيقاف هذا التنزيل مؤقتاً — الخادم لا يدعم ذلك.'
                : "This download can't be paused — the server doesn't support it.",
          ),
        ),
      );
    }
  }

  /// The circular button near the play button: a plain download icon while
  /// nothing has been fetched yet; while queued/downloading/paused, a
  /// progress spinner or play icon that toggles pause/resume on tap and
  /// cancels on long-press; or "Play Offline" once it has finished —
  /// reverting back to the plain download icon if the download is deleted.
  Widget _buildDownloadButton(
    BuildContext context,
    DownloadsProvider downloads,
    String mediaId,
    String sourceUrl,
    AppColors colors,
    bool isArabic,
  ) {
    if (downloads.isDownloaded(mediaId)) {
      return IconButton(
        icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.black),
        tooltip: isArabic ? 'تشغيل دون اتصال' : 'Play Offline',
        onPressed: () => _openPlayer(context, offline: true),
      );
    }

    if (downloads.isDownloading(mediaId)) {
      final item = downloads.itemFor(mediaId)!;
      final isPaused = item.status == DownloadStatus.paused;
      final isPausing = _pausingIds.contains(mediaId);
      final canPause = DownloadsProvider.pauseSupported;
      return IconButton(
        icon: isPaused
            ? const Icon(Icons.play_arrow_rounded, color: Colors.black)
            : SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  value:
                      !isPausing &&
                          item.status == DownloadStatus.downloading &&
                          item.totalBytes > 0
                      ? item.progress
                      : null,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colors.brandPrimary,
                  ),
                ),
              ),
        tooltip: !canPause
            ? (isArabic ? 'إلغاء التنزيل' : 'Cancel Download')
            : isPaused
            ? (isArabic ? 'استئناف التنزيل' : 'Resume Download')
            : (isArabic ? 'إيقاف التنزيل مؤقتاً' : 'Pause Download'),
        onPressed: !canPause
            ? () => downloads.cancelDownload(mediaId)
            : isPausing
            ? null
            : () => isPaused
                  ? downloads.resumeDownload(mediaId)
                  : _pause(context, downloads, mediaId),
        onLongPress: canPause ? () => downloads.cancelDownload(mediaId) : null,
      );
    }

    return IconButton(
      icon: const Icon(Icons.download_rounded, color: Colors.black),
      tooltip: isArabic ? 'تنزيل' : 'Download',
      onPressed: () {
        downloads.startDownload(
          id: mediaId,
          title: widget.movie.name,
          posterUrl: widget.movie.streamIcon,
          type: MediaType.movie,
          sourceUrl: sourceUrl,
          rawData: widget.movie.toJson(),
        );
      },
    );
  }
}
