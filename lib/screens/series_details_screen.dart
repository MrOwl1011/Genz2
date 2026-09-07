import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../core/build_flavor.dart' show kIsTv;
import '../models/download_item.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/downloads_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../core/resume_season.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../widgets/dialog_buttons.dart';
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
  // Ids currently awaiting DownloadsProvider.pauseDownload's server-support
  // check — that can take several seconds (see the comment there), so the
  // pause button shows a spinner instead of looking frozen/unresponsive.
  final Set<String> _pausingIds = {};

  /// Which season's episodes are listed. Null until the series loads, then
  /// the lowest-numbered season.
  int? _selectedSeason;

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
          // Open on the season the viewer is partway through, so arriving
          // from Continue Watching lands on the episodes around the one they
          // were watching. Falls back to the first season for a series they
          // have not started.
          final seasons = info?.episodes.keys.toList() ?? <int>[];
          seasons.sort();
          _selectedSeason = seasons.isEmpty
              ? null
              : resumeSeasonFor(
                      history: context.read<UserPrefsProvider>().history,
                      seriesId: widget.series.seriesId,
                      availableSeasons: seasons,
                    ) ??
                    seasons.first;
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
    final isArabic = userPrefs.locale == 'ar';

    String urlFor(XtreamEpisode ep) {
      final localPath = downloads.isDownloaded(ep.id)
          ? downloads.itemFor(ep.id)?.filePath
          : null;
      if (localPath != null) return Uri.file(localPath).toString();
      return ep.streamUrl(content.baseUrl, content.username, content.password);
    }

    final url = urlFor(episode);

    int position = userPrefs.getHistoryPosition(episode.id);

    // Show resume dialog if position > 30 seconds
    if (position > 30) {
      final result = await showResumeDialog(
        context,
        position,
        episodeLabel: isArabic
            ? 'الموسم ${episode.season} · الحلقة ${episode.episodeNum}'
            : 'Season ${episode.season} · Episode ${episode.episodeNum}',
      );
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
        final sortedEps = List<XtreamEpisode>.from(eps)
          ..sort((a, b) => a.episodeNum.compareTo(b.episodeNum));
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

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(
              streamUrl: url,
              title:
                  'S${episode.season} E${episode.episodeNum} - ${episode.title}',
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
        )
        .then((_) {
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
      (h) =>
          h!.type == MediaType.series &&
          h.rawData['series_id'] == widget.series.seriesId,
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
    final firstSeason = _seriesInfo!.episodes.keys.reduce(
      (a, b) => a < b ? a : b,
    );
    final firstEp = _seriesInfo!.episodes[firstSeason]?.first;
    if (firstEp != null) _playEpisode(firstEp);
  }

  /// Height of the details card, which the action buttons are anchored to.
  ///
  /// Shared by the card itself and by the Positioned that places the buttons
  /// at its top edge, so the two can never disagree about where that edge is.
  double _cardHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * (kIsTv ? 0.78 : 0.55);

  @override
  Widget build(BuildContext context) {
    final title = _seriesInfo?.info.name ?? widget.series.name;
    final cover = _seriesInfo?.info.cover ?? widget.series.cover;
    final plot = _seriesInfo?.info.plot ?? widget.series.plot;
    final cast = _seriesInfo?.info.cast ?? widget.series.cast;
    final director = _seriesInfo?.info.director ?? widget.series.director;
    final genre = _seriesInfo?.info.genre ?? widget.series.genre;
    final releaseDate =
        _seriesInfo?.info.releaseDate ?? widget.series.releaseDate;

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
              height: _cardHeight(context),
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Play/Like Buttons (Overlapping top edge) — download is
                  // handled per-episode below instead of once for the whole
                  // series.

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
                                    // Poster — same treatment as the movie
                                    // detail page, so the two pages are one
                                    // template with different data.
                                    Container(
                                      width: kIsTv ? 76 : 108,
                                      height: kIsTv ? 114 : 162,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: colors.ink.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
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
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppType.hero(colors.ink)
                                                .copyWith(
                                                  fontSize: kIsTv ? 22 : 26,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            [releaseDate, genre]
                                                .where((v) => v.isNotEmpty)
                                                .join('  ·  '),
                                            maxLines: 2,
                                            style: AppType.meta(
                                              colors.ink.withValues(
                                                alpha: 0.55,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: kIsTv ? 12 : 18),
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
                                    style: AppType.sans(
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
                                    style: AppType.body(
                                      colors.ink.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (director.isNotEmpty) ...[
                                  Text(
                                    director,
                                    style: AppType.body(
                                      colors.ink.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                // Episodes Section
                                if (_seriesInfo != null &&
                                    _seriesInfo!.episodes.isNotEmpty)
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
          // The action buttons, straddling the details card's top edge.
          //
          // They used to live inside that card's own Stack at `top: -36` with
          // clipBehavior: Clip.none. That paints them correctly but leaves
          // the top half untappable: Flutter's hit testing rejects any
          // pointer outside a render box's own bounds no matter how its
          // children are clipped, so half of a 72pt Play button was dead and
          // taps landed roughly one time in two.
          //
          // Here they are inside their parent, so every pixel is hittable —
          // and they come last among the Stack's children deliberately.
          // Children paint in order, so anchoring them earlier put them
          // behind the very surface they are meant to overlap; last also
          // means they are hit-tested first.
          Positioned(
            bottom: _cardHeight(context) - 36,
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
                      focusColor: colors.brandAccent.withValues(alpha: 0.35),
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
                      focusColor: Colors.white.withValues(alpha: 0.35),
                      // TV: see the same fix + rationale in
                      // movie_details_screen.dart — autofocusing
                      // Play avoids the back button being an
                      // unreachable directional-focus dead end.
                      autofocus: kIsTv,
                      onTap: () => _playResumeOrFirst(),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the season list as a bottom sheet.
  ///
  /// A sheet rather than a DropdownButton: Material's dropdown menu is styled
  /// by the Material theme rather than this app's tokens, and its overlay
  /// becomes unusable past roughly a dozen entries. A sheet scrolls, matches
  /// the app's own sheet treatment, and is what every streaming app on the
  /// platform uses for the same job.
  Future<void> _showSeasonPicker(List<int> seasons, bool isArabic) async {
    final colors = context.colors;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    isArabic ? 'المواسم' : 'SEASONS',
                    style: AppType.meta(colors.ink.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: seasons.length,
                  itemBuilder: (_, i) {
                    final season = seasons[i];
                    final selected = season == _selectedSeason;
                    final count = _seriesInfo?.episodes[season]?.length ?? 0;
                    return ListTile(
                      onTap: () => Navigator.of(sheetContext).pop(season),
                      // The current season is marked by a leading brand bar,
                      // matching how the app marks "current" everywhere else.
                      leading: Container(
                        width: 3,
                        height: 22,
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.brandPrimary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      title: Text(
                        isArabic ? 'الموسم $season' : 'Season $season',
                        style: AppType.cardTitle(
                          colors.ink.withValues(alpha: selected ? 1 : 0.75),
                        ),
                      ),
                      trailing: Text(
                        isArabic ? '$count حلقة' : '$count episodes',
                        style: AppType.meta(colors.ink.withValues(alpha: 0.45)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (picked != null && mounted && picked != _selectedSeason) {
      setState(() => _selectedSeason = picked);
    }
  }

  List<Widget> _buildEpisodesList() {
    final colors = context.colors;
    final List<Widget> items = [];
    final sortedSeasons = _seriesInfo!.episodes.keys.toList()..sort();
    final userPrefs = context
        .read<UserPrefsProvider>(); // read history for progress
    final isArabic = userPrefs.locale == 'ar';
    final content = context.read<ContentProvider>();
    final downloads = context.watch<DownloadsProvider>();

    // Every season used to be concatenated into one list with a header
    // between each. A long-running series put hundreds of episodes on a
    // single scroll, and reaching season 5 meant scrolling past four
    // seasons of it. One season at a time, chosen from a selector.
    final season =
        _selectedSeason ?? (sortedSeasons.isEmpty ? null : sortedSeasons.first);
    if (season != null) {
      final episodes = _seriesInfo!.episodes[season] ?? const [];
      episodes.sort((a, b) => a.episodeNum.compareTo(b.episodeNum));

      items.add(
        _SeasonSelector(
          season: season,
          seasonCount: sortedSeasons.length,
          episodeCount: episodes.length,
          isArabic: isArabic,
          // A single season needs no control — showing a picker that can
          // only pick what is already selected is noise.
          onTap: sortedSeasons.length < 2
              ? null
              : () => _showSeasonPicker(sortedSeasons, isArabic),
        ),
      );

      for (final ep in episodes) {
        final position = userPrefs.getHistoryPosition(ep.id);

        items.add(
          ListTile(
            contentPadding: EdgeInsets.zero,
            // ListTile already participates in D-pad focus traversal and
            // responds to Select/Enter out of the box — the default focus
            // tint is too subtle to see from a TV viewing distance, so make
            // it obvious instead of adding a whole extra focus wrapper.
            focusColor: colors.brandAccent.withValues(alpha: 0.18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  ep.episodeNum.toString(),
                  style: AppType.cardTitle(colors.ink),
                ),
              ),
            ),
            title: Text(
              ep.title.isNotEmpty
                  ? ep.title
                  : (isArabic
                        ? 'الحلقة ${ep.episodeNum}'
                        : 'Episode ${ep.episodeNum}'),
              style: AppType.cardTitle(colors.ink),
            ),
            subtitle: position > 0
                ? Text(
                    isArabic
                        ? 'شوهد ${position ~/ 60} د'
                        : 'Watched ${position ~/ 60}m',
                    style: AppType.caption(colors.brandPrimary),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildEpisodeDownloadButton(
                  context,
                  downloads,
                  content,
                  ep,
                  colors,
                  isArabic,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: colors.ink.withValues(alpha: 0.54),
                ),
              ],
            ),
            onTap: () => _playEpisode(ep),
          ),
        );
      }
    }
    return items;
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

  /// Per-episode download control: plain download icon → progress spinner
  /// (tap to cancel) while in flight → "Play Offline" once complete,
  /// reverting to the plain download icon again if it's deleted.
  Widget _buildEpisodeDownloadButton(
    BuildContext context,
    DownloadsProvider downloads,
    ContentProvider content,
    XtreamEpisode ep,
    AppColors colors,
    bool isArabic,
  ) {
    if (downloads.isDownloaded(ep.id)) {
      return IconButton(
        icon: const Icon(Icons.offline_pin_rounded),
        color: colors.brandPrimary,
        tooltip: isArabic ? 'تشغيل دون اتصال' : 'Play Offline',
        onPressed: () => _playEpisode(ep),
      );
    }

    if (downloads.isDownloading(ep.id)) {
      final item = downloads.itemFor(ep.id)!;
      final isPaused = item.status == DownloadStatus.paused;
      final isPausing = _pausingIds.contains(ep.id);
      final canPause = DownloadsProvider.pauseSupported;
      return IconButton(
        icon: isPaused
            ? Icon(Icons.play_arrow_rounded, color: colors.brandPrimary)
            : SizedBox(
                width: 20,
                height: 20,
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
            ? () => downloads.cancelDownload(ep.id)
            : isPausing
            ? null
            : () => isPaused
                  ? downloads.resumeDownload(ep.id)
                  : _pause(context, downloads, ep.id),
        onLongPress: canPause ? () => downloads.cancelDownload(ep.id) : null,
      );
    }

    final sourceUrl = ep.streamUrl(
      content.baseUrl,
      content.username,
      content.password,
    );
    if (!DownloadsProvider.isDownloadable(sourceUrl)) {
      // HLS (.m3u8) sources can't be saved as a single playable offline
      // file — see DownloadsProvider.isDownloadable — so don't offer an
      // action that would silently produce a broken "download".
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: Icon(
        Icons.download_rounded,
        color: colors.ink.withValues(alpha: 0.54),
      ),
      tooltip: isArabic ? 'تنزيل' : 'Download',
      onPressed: () => _promptDownloadChoice(context, downloads, content, ep),
    );
  }

  /// Entry point for downloading a series episode: ask whether the user
  /// wants just the tapped episode or a hand-picked batch of episodes across
  /// seasons, rather than only ever offering one at a time.
  void _promptDownloadChoice(
    BuildContext context,
    DownloadsProvider downloads,
    ContentProvider content,
    XtreamEpisode ep,
  ) {
    final colors = context.colors;
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isArabic ? 'تنزيل الحلقات' : 'Download Episodes',
          style: AppType.cardTitle(colors.ink),
        ),
        content: Text(
          isArabic
              ? 'تنزيل هذه الحلقة فقط، أم اختيار عدة حلقات لتنزيلها معاً؟'
              : 'Download just this episode, or pick several episodes to download together?',
          style: AppType.body(colors.ink.withValues(alpha: 0.7)),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          DialogSecondaryButton(
            label: isArabic ? 'هذه الحلقة' : 'This Episode',
            onPressed: () {
              Navigator.of(ctx).pop();
              _downloadEpisode(downloads, content, ep);
            },
          ),
          DialogPrimaryButton(
            label: isArabic ? 'اختيار حلقات...' : 'Select Episodes...',
            onPressed: () {
              Navigator.of(ctx).pop();
              _showMultiEpisodeDownloadSheet(context, downloads, content);
            },
          ),
        ],
      ),
    );
  }

  void _downloadEpisode(
    DownloadsProvider downloads,
    ContentProvider content,
    XtreamEpisode ep,
  ) {
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
    downloads.startDownload(
      id: ep.id,
      title: ep.title.isNotEmpty
          ? ep.title
          : (isArabic ? 'الحلقة ${ep.episodeNum}' : 'Episode ${ep.episodeNum}'),
      posterUrl: widget.series.cover,
      type: MediaType.series,
      sourceUrl: ep.streamUrl(
        content.baseUrl,
        content.username,
        content.password,
      ),
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
  }

  /// A modal, per-season checklist of episodes, letting the user queue many
  /// downloads in one go instead of tapping every episode's button
  /// individually. Already-downloaded/in-progress or non-downloadable (HLS)
  /// episodes are shown but disabled.
  void _showMultiEpisodeDownloadSheet(
    BuildContext context,
    DownloadsProvider downloads,
    ContentProvider content,
  ) {
    final colors = context.colors;
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
    final selected = <String>{};
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final sortedSeasons = _seriesInfo!.episodes.keys.toList()..sort();
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              isArabic ? 'اختيار الحلقات' : 'SELECT EPISODES',
                              style: AppType.rowHeader(colors.ink),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(
                              isArabic ? 'إلغاء' : 'Cancel',
                              style: AppType.body(
                                colors.ink.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (final season in sortedSeasons) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                              child: Text(
                                isArabic ? 'الموسم $season' : 'SEASON $season',
                                style: AppType.sans(
                                  fontWeight: FontWeight.w800,
                                  color: colors.brandPrimary,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            ...(_seriesInfo!.episodes[season]!..sort(
                                  (a, b) =>
                                      a.episodeNum.compareTo(b.episodeNum),
                                ))
                                .map((ep) {
                                  final already =
                                      downloads.isDownloaded(ep.id) ||
                                      downloads.isDownloading(ep.id);
                                  final sourceUrl = ep.streamUrl(
                                    content.baseUrl,
                                    content.username,
                                    content.password,
                                  );
                                  final downloadable =
                                      DownloadsProvider.isDownloadable(
                                        sourceUrl,
                                      );
                                  final enabled = !already && downloadable;
                                  return CheckboxListTile(
                                    value: selected.contains(ep.id),
                                    enabled: enabled,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    activeColor: colors.brandPrimary,
                                    onChanged: enabled
                                        ? (v) => setSheetState(() {
                                            if (v == true) {
                                              selected.add(ep.id);
                                            } else {
                                              selected.remove(ep.id);
                                            }
                                          })
                                        : null,
                                    title: Text(
                                      ep.title.isNotEmpty
                                          ? ep.title
                                          : (isArabic
                                                ? 'الحلقة ${ep.episodeNum}'
                                                : 'Episode ${ep.episodeNum}'),
                                      style: AppType.body(colors.ink),
                                    ),
                                    subtitle: already
                                        ? Text(
                                            isArabic
                                                ? 'تم تنزيلها بالفعل'
                                                : 'Already downloaded',
                                            style: AppType.caption(
                                              colors.ink.withValues(alpha: 0.4),
                                            ),
                                          )
                                        : (!downloadable
                                              ? Text(
                                                  isArabic
                                                      ? 'غير قابلة للتنزيل'
                                                      : 'Not downloadable',
                                                  style: AppType.caption(
                                                    colors.ink.withValues(
                                                      alpha: 0.4,
                                                    ),
                                                  ),
                                                )
                                              : null),
                                  );
                                }),
                          ],
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.brandPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: selected.isEmpty
                                ? null
                                : () {
                                    Navigator.of(ctx).pop();
                                    _downloadEpisodes(
                                      downloads,
                                      content,
                                      selected,
                                    );
                                  },
                            child: Text(
                              selected.isEmpty
                                  ? (isArabic
                                        ? 'اختر حلقات للتنزيل'
                                        : 'Select episodes to download')
                                  : (isArabic
                                        ? 'تنزيل ${selected.length} حلقة'
                                        : 'Download ${selected.length} Episode${selected.length == 1 ? '' : 's'}'),
                              style: AppType.cardTitle(Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _downloadEpisodes(
    DownloadsProvider downloads,
    ContentProvider content,
    Set<String> ids,
  ) {
    if (_seriesInfo == null) return;
    for (final episodes in _seriesInfo!.episodes.values) {
      for (final ep in episodes) {
        if (ids.contains(ep.id)) {
          _downloadEpisode(downloads, content, ep);
        }
      }
    }
  }
}

/// The control that opens the season picker, and the header for the list
/// beneath it.
///
/// Reads as one line of type plus a chevron rather than a bordered form
/// field: it sits above content, not inside a form, and a boxed input here
/// would compete with the episode rows it introduces.
class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.season,
    required this.seasonCount,
    required this.episodeCount,
    required this.isArabic,
    required this.onTap,
  });

  final int season;
  final int seasonCount;
  final int episodeCount;
  final bool isArabic;

  /// Null when there is only one season, which renders the row as a plain
  /// heading with no affordance.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  isArabic ? 'الموسم $season' : 'Season $season',
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowHeader(colors.ink),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 22,
                  color: colors.ink.withValues(alpha: 0.6),
                ),
              ],
              const Spacer(),
              Text(
                isArabic ? '$episodeCount حلقة' : '$episodeCount episodes',
                style: AppType.meta(colors.ink.withValues(alpha: 0.45)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
