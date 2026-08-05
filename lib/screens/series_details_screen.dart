import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_dialog.dart';
import 'player_screen.dart';

class SeriesDetailsScreen extends StatefulWidget {
  final XtreamSeries series;

  const SeriesDetailsScreen({super.key, required this.series});

  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> {
  XtreamSeriesInfo? _seriesInfo;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSeriesInfo();
  }

  Future<void> _loadSeriesInfo() async {
    try {
      final content = context.read<ContentProvider>();
      final info = await content.getSeriesInfo(widget.series.seriesId);
      if (mounted) {
        setState(() {
          _seriesInfo = info;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Plays an episode with resume dialog support.
  /// Shows a dialog if saved position > 30 seconds. Transparently prefers
  /// the downloaded local copy over the network stream, for this episode
  /// and any other downloaded episode in the auto-play-next playlist.
  void _playEpisode(XtreamEpisode episode) async {
    final content = context.read<ContentProvider>();
    final userPrefs = context.read<UserPrefsProvider>();
    final downloads = context.read<DownloadsProvider>();

    String urlFor(XtreamEpisode ep) {
      final localPath = downloads.isDownloaded(ep.id) ? downloads.itemFor(ep.id)?.filePath : null;
      if (localPath != null) return Uri.file(localPath).toString();
      return ep.streamUrl(content.baseUrl, content.username, content.password);
    }

    final url = urlFor(episode);

    int position = userPrefs.getHistoryPosition(episode.id);

    // Show resume dialog if position > 30 seconds
    if (position > 30) {
      final result = await showResumeDialog(context, position);
      if (!mounted) return;
      if (result == null) {
        return; // dismissed via X or outside tap — cancelled, don't open the player
      }
      if (result == false) {
        position = 0; // User chose "Start Over"
        userPrefs.clearHistoryPosition(episode.id);
      }
    }

    // Create a playlist of all episodes sorted
    final List<Map<String, dynamic>> playlist = [];
    int initialIndex = 0;

    if (_seriesInfo != null) {
      final sortedSeasons = _seriesInfo!.episodes.keys.toList()..sort();
      for (final s in sortedSeasons) {
        final eps = _seriesInfo!.episodes[s]!;
        // Assuming they are already sorted or we can sort them
        final sortedEps = List<XtreamEpisode>.from(eps)..sort((a, b) => a.episodeNum.compareTo(b.episodeNum));
        for (final ep in sortedEps) {
          if (ep.id == episode.id) {
            initialIndex = playlist.length;
          }
          playlist.add({
            'url': urlFor(ep),
            'title': 'S${ep.season} E${ep.episodeNum} - ${ep.title}',
            'coverUrl': widget.series.cover,
            'isLive': false,
            'mediaId': ep.id,
            'mediaType': MediaType.series,
            'rawMediaData': {
              'id': ep.id,
              'episode_num': ep.episodeNum,
              'title': ep.title,
              'container_extension': ep.containerExtension,
              'info': ep.info,
              'custom_sid': ep.customSid,
              'added': ep.added,
              'season': ep.season,
              'series_id': widget.series.seriesId,
              'series_name': widget.series.name,
              'series_cover': widget.series.cover,
            },
          });
        }
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: url,
          title: 'S${episode.season} E${episode.episodeNum} - ${episode.title}',
          coverUrl: widget.series.cover,
          isLive: false,
          mediaId: episode.id,
          mediaType: MediaType.series,
          rawMediaData: {
            'id': episode.id,
            'episode_num': episode.episodeNum,
            'title': episode.title,
            'container_extension': episode.containerExtension,
            'info': episode.info,
            'custom_sid': episode.customSid,
            'added': episode.added,
            'season': episode.season,
            'series_id': widget.series.seriesId,
            'series_name': widget.series.name,
            'series_cover': widget.series.cover,
          },
          initialPositionSeconds: position,
          playlist: playlist.isNotEmpty ? playlist : null,
          initialIndex: initialIndex,
        ),
      ),
    ).then((_) {
      setState(() {});
    });
  }

  /// Resumes from the last watched episode for this series.
  /// Falls back to the first episode if no history exists.
  void _playResumeOrFirst() {
    if (_seriesInfo == null || _seriesInfo!.episodes.isEmpty) return;

    final userPrefs = context.read<UserPrefsProvider>();
    // Find the last watched episode for this series in history
    final historyItem = userPrefs.history.cast<HistoryItem?>().firstWhere(
      (h) => h!.type == MediaType.series && h.rawData['series_id'] == widget.series.seriesId,
      orElse: () => null,
    );

    if (historyItem != null) {
      // Find the matching episode in the loaded series info
      for (final seasonEps in _seriesInfo!.episodes.values) {
        for (final ep in seasonEps) {
          if (ep.id == historyItem.id) {
            _playEpisode(ep);
            return;
          }
        }
      }
    }

    // Fallback: play first episode of first season
    final firstSeason = _seriesInfo!.episodes.keys.reduce((a, b) => a < b ? a : b);
    final firstEp = _seriesInfo!.episodes[firstSeason]?.first;
    if (firstEp != null) _playEpisode(firstEp);
  }

  @override
  Widget build(BuildContext context) {
    final title = _seriesInfo?.info.name ?? widget.series.name;
    final cover = _seriesInfo?.info.cover ?? widget.series.cover;
    final plot = _seriesInfo?.info.plot ?? widget.series.plot;
    final cast = _seriesInfo?.info.cast ?? widget.series.cast;
    final director = _seriesInfo?.info.director ?? widget.series.director;
    final genre = _seriesInfo?.info.genre ?? widget.series.genre;
    final releaseDate = _seriesInfo?.info.releaseDate ?? widget.series.releaseDate;

    final userPrefs = context.watch<UserPrefsProvider>();
    final isFav = userPrefs.isFavorite(widget.series.seriesId.toString());
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          // Background Poster
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.55,
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
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Draggable/Scrollable Details Card
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.55,
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
                  // Play/Like Buttons (Overlapping top edge) — download is
                  // handled per-episode below instead of once for the whole
                  // series.
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
                                color: isFav ? colors.brandPrimary : Colors.black,
                              ),
                              onPressed: () {
                                userPrefs.toggleFavorite(
                                  id: widget.series.seriesId.toString(),
                                  title: widget.series.name,
                                  posterUrl: widget.series.cover,
                                  type: MediaType.series,
                                  rawData: {
                                    'series_id': widget.series.seriesId,
                                    'name': widget.series.name,
                                    'cover': widget.series.cover,
                                    'category_id': widget.series.categoryId,
                                    'plot': widget.series.plot,
                                    'cast': widget.series.cast,
                                    'director': widget.series.director,
                                    'genre': widget.series.genre,
                                    'releaseDate': widget.series.releaseDate,
                                    'rating': widget.series.rating,
                                    'last_modified': widget.series.lastModified,
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          // See the same fix in movie_details_screen.dart:
                          // Material+InkWell hit-tests the full square, unlike
                          // a GestureDetector deferring to a circular child
                          // (which only accepts taps inside the inscribed
                          // circle and drops corner taps).
                          Material(
                            color: colors.brandPrimary,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _playResumeOrFirst(),
                              child: const SizedBox(
                                width: 72,
                                height: 72,
                                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
                              ),
                            ),
                          ),
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
                              valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
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
                                      width: 100,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        image: DecorationImage(
                                          image: CachedNetworkImageProvider(cover),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title.toUpperCase(),
                                            style: GoogleFonts.outfit(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                              fontStyle: FontStyle.italic,
                                              color: colors.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (releaseDate.isNotEmpty)
                                            Text(
                                              releaseDate,
                                              style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7)),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (genre.isNotEmpty)
                                  Text(
                                    genre,
                                    style: GoogleFonts.outfit(
                                      color: colors.ink,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                if (plot.isNotEmpty)
                                  Text(
                                    plot,
                                    style: GoogleFonts.outfit(
                                      color: colors.brandPrimary, // Brand-colored description per user request
                                      fontSize: 15,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.justify,
                                  ),
                                const SizedBox(height: 16),
                                if (cast.isNotEmpty) ...[
                                  Text(
                                    cast,
                                    style: GoogleFonts.outfit(
                                      color: colors.ink.withValues(alpha: 0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (director.isNotEmpty) ...[
                                  Text(
                                    director,
                                    style: GoogleFonts.outfit(
                                      color: colors.ink.withValues(alpha: 0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                // Episodes Section
                                if (_seriesInfo != null && _seriesInfo!.episodes.isNotEmpty)
                                  ..._buildEpisodesList(),

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

  List<Widget> _buildEpisodesList() {
    final colors = context.colors;
    final List<Widget> items = [];
    final sortedSeasons = _seriesInfo!.episodes.keys.toList()..sort();
    final userPrefs = context.read<UserPrefsProvider>(); // read history for progress
    final content = context.read<ContentProvider>();
    final downloads = context.watch<DownloadsProvider>();

    for (final season in sortedSeasons) {
      final episodes = _seriesInfo!.episodes[season]!;
      episodes.sort((a, b) => a.episodeNum.compareTo(b.episodeNum));

      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Text(
            'SEASON $season',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: colors.brandPrimary,
              letterSpacing: 1.5,
            ),
          ),
        ),
      );

      for (final ep in episodes) {
        final position = userPrefs.getHistoryPosition(ep.id);

        items.add(
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  ep.episodeNum.toString(),
                  style: GoogleFonts.outfit(
                    color: colors.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            title: Text(
              ep.title.isNotEmpty ? ep.title : 'Episode ${ep.episodeNum}',
              style: GoogleFonts.outfit(
                color: colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: position > 0
                ? Text('Watched ${position ~/ 60}m', style: TextStyle(color: colors.brandPrimary, fontSize: 12))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildEpisodeDownloadButton(context, downloads, content, ep, colors),
                const SizedBox(width: 4),
                Icon(Icons.play_circle_fill_rounded, color: colors.ink.withValues(alpha: 0.54)),
              ],
            ),
            onTap: () => _playEpisode(ep),
          ),
        );
      }
    }
    return items;
  }

  /// Per-episode download control: plain download icon → progress spinner
  /// (tap to cancel) while in flight → "Play Offline" once complete,
  /// reverting to the plain download icon again if it's deleted.
  Widget _buildEpisodeDownloadButton(
    BuildContext context,
    DownloadsProvider downloads,
    ContentProvider content,
    XtreamEpisode ep,
    AppColors colors,
  ) {
    if (downloads.isDownloaded(ep.id)) {
      return IconButton(
        icon: const Icon(Icons.offline_pin_rounded),
        color: colors.brandPrimary,
        tooltip: 'Play Offline',
        onPressed: () => _playEpisode(ep),
      );
    }

    if (downloads.isDownloading(ep.id)) {
      final item = downloads.itemFor(ep.id)!;
      return IconButton(
        icon: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: item.totalBytes > 0 ? item.progress : null,
            valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
          ),
        ),
        tooltip: 'Cancel Download',
        onPressed: () => downloads.cancelDownload(ep.id),
      );
    }

    final sourceUrl = ep.streamUrl(content.baseUrl, content.username, content.password);
    if (!DownloadsProvider.isDownloadable(sourceUrl)) {
      // HLS (.m3u8) sources can't be saved as a single playable offline
      // file — see DownloadsProvider.isDownloadable — so don't offer an
      // action that would silently produce a broken "download".
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(Icons.download_rounded, color: colors.ink.withValues(alpha: 0.54)),
      tooltip: 'Download',
      onPressed: () {
        downloads.startDownload(
          id: ep.id,
          title: ep.title.isNotEmpty ? ep.title : 'Episode ${ep.episodeNum}',
          posterUrl: widget.series.cover,
          type: MediaType.series,
          sourceUrl: sourceUrl,
          rawData: {
            'id': ep.id,
            'episode_num': ep.episodeNum,
            'title': ep.title,
            'container_extension': ep.containerExtension,
            'info': ep.info,
            'custom_sid': ep.customSid,
            'added': ep.added,
            'season': ep.season,
            'series_id': widget.series.seriesId,
            'series_name': widget.series.name,
            'series_cover': widget.series.cover,
          },
        );
      },
    );
  }
}
