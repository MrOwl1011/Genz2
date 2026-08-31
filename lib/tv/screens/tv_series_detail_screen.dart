import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/xtream_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/downloads_provider.dart';
import '../../providers/user_prefs_provider.dart';
import '../../screens/player_screen.dart';
import '../../theme/app_colors.dart';
import '../../widgets/resume_dialog.dart';
import '../tv_metrics.dart';
import '../tv_route.dart';
import '../widgets/tv_detail_action_button.dart';
import '../widgets/tv_focus.dart';

/// TV-native series detail screen: a small poster beside its title,
/// metadata, description and actions (same treatment as
/// TvMovieDetailScreen), with the season picker and episode list below —
/// no separate More-Like-This/Cast tabs (see the identical note on
/// TvMovieDetailScreen for why).
class TvSeriesDetailScreen extends StatefulWidget {
  final XtreamSeries series;

  const TvSeriesDetailScreen({super.key, required this.series});

  @override
  State<TvSeriesDetailScreen> createState() => _TvSeriesDetailScreenState();
}

class _TvSeriesDetailScreenState extends State<TvSeriesDetailScreen> {
  XtreamSeriesInfo? _seriesInfo;
  bool _isLoading = true;
  int _season = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final content = context.read<ContentProvider>();
      final info = await content.getSeriesInfo(widget.series.seriesId);
      if (mounted) {
        setState(() {
          _seriesInfo = info;
          if (info != null && info.episodes.isNotEmpty) {
            _season = (info.episodes.keys.toList()..sort()).first;
          }
        });
      }
    } catch (_) {
      // Non-fatal — falls back to widget.series's own fields below.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _urlFor(XtreamEpisode ep) {
    final content = context.read<ContentProvider>();
    final downloads = context.read<DownloadsProvider>();
    final localPath = downloads.isDownloaded(ep.id)
        ? downloads.itemFor(ep.id)?.filePath
        : null;
    if (localPath != null) return Uri.file(localPath).toString();
    return ep.streamUrl(content.baseUrl, content.username, content.password);
  }

  Future<void> _playEpisode(XtreamEpisode episode) async {
    final userPrefs = context.read<UserPrefsProvider>();
    final isArabic = userPrefs.locale == 'ar';
    final url = _urlFor(episode);
    int position = userPrefs.getHistoryPosition(episode.id);

    if (position > 30) {
      final result = await showResumeDialog(
        context,
        position,
        episodeLabel: isArabic
            ? 'الموسم ${episode.season} · الحلقة ${episode.episodeNum}'
            : 'Season ${episode.season} · Episode ${episode.episodeNum}',
      );
      if (!mounted) return;
      if (result == null) return;
      if (result == false) {
        position = 0;
        userPrefs.clearHistoryPosition(episode.id);
      }
    }

    // Cross-season playlist so the player's auto-play-next carries on past
    // the end of whichever season this episode happens to be in — matches
    // series_details_screen.dart's _playEpisode exactly.
    final playlist = <Map<String, dynamic>>[];
    var initialIndex = 0;
    final info = _seriesInfo;
    if (info != null) {
      final sortedSeasons = info.episodes.keys.toList()..sort();
      for (final s in sortedSeasons) {
        final eps = List<XtreamEpisode>.from(info.episodes[s]!)
          ..sort((a, b) => a.episodeNum.compareTo(b.episodeNum));
        for (final ep in eps) {
          if (ep.id == episode.id) initialIndex = playlist.length;
          playlist.add({
            'url': _urlFor(ep),
            'title': 'S${ep.season} E${ep.episodeNum} - ${ep.title}',
            'coverUrl': widget.series.cover,
            'isLive': false,
            'mediaId': ep.id,
            'mediaType': MediaType.series,
            'rawMediaData': _episodeRawData(ep),
          });
        }
      }
    }

    if (!mounted) return;
    pushTv(
      context,
      PlayerScreen(
        streamUrl: url,
        title: 'S${episode.season} E${episode.episodeNum} - ${episode.title}',
        coverUrl: widget.series.cover,
        isLive: false,
        mediaId: episode.id,
        mediaType: MediaType.series,
        rawMediaData: _episodeRawData(episode),
        initialPositionSeconds: position,
        playlist: playlist.isNotEmpty ? playlist : null,
        initialIndex: initialIndex,
      ),
    );
  }

  Map<String, dynamic> _episodeRawData(XtreamEpisode ep) => {
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
  };

  /// The episode Play/Download from the top action row act on: whichever
  /// one has an in-progress watch position, or the first episode of the
  /// first season otherwise. Shared by both buttons so "Download" always
  /// grabs the same episode "Play" would resume/start with.
  XtreamEpisode? _resumeOrFirstEpisode() {
    final info = _seriesInfo;
    if (info == null || info.episodes.isEmpty) return null;
    final userPrefs = context.read<UserPrefsProvider>();

    final history = userPrefs.history.cast<HistoryItem?>().firstWhere(
      (h) =>
          h!.type == MediaType.series &&
          h.rawData['series_id'] == widget.series.seriesId,
      orElse: () => null,
    );
    if (history != null) {
      for (final eps in info.episodes.values) {
        for (final ep in eps) {
          if (ep.id == history.id) return ep;
        }
      }
    }

    final firstSeason = info.episodes.keys.reduce((a, b) => a < b ? a : b);
    return info.episodes[firstSeason]?.first;
  }

  void _playResumeOrFirst() {
    final ep = _resumeOrFirstEpisode();
    if (ep != null) _playEpisode(ep);
  }

  void _downloadEpisode(DownloadsProvider downloads, XtreamEpisode ep) {
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
    downloads.startDownload(
      id: ep.id,
      title: ep.title.isNotEmpty
          ? ep.title
          : (isArabic ? 'الحلقة ${ep.episodeNum}' : 'Episode ${ep.episodeNum}'),
      posterUrl: widget.series.cover,
      type: MediaType.series,
      sourceUrl: _urlFor(ep),
      rawData: _episodeRawData(ep),
    );
  }

  /// Unlike a movie — one title, one file, so its Download button just
  /// starts that one download — a series has many episodes and no single
  /// obvious thing to download, so this asks which ones first.
  Future<void> _pickEpisodesToDownload() async {
    final info = _seriesInfo;
    if (info == null) return;
    final episodes = List<XtreamEpisode>.from(
      info.episodes[_season] ?? const [],
    )..sort((a, b) => a.episodeNum.compareTo(b.episodeNum));
    if (episodes.isEmpty) return;

    final downloads = context.read<DownloadsProvider>();
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';

    final selected = await showDialog<List<XtreamEpisode>>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _EpisodeDownloadPicker(
        episodes: episodes,
        season: _season,
        downloads: downloads,
        isArabic: isArabic,
        isDownloadable: (ep) => DownloadsProvider.isDownloadable(_urlFor(ep)),
      ),
    );

    if (selected == null || !mounted) return;
    for (final ep in selected) {
      _downloadEpisode(downloads, ep);
    }
  }

  Future<void> _pickSeason(List<int> seasons) async {
    final colors = context.colors;
    final picked = await showDialog<int>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in seasons)
                  TvFocusScope(
                    autofocus: s == _season,
                    onTap: () => Navigator.of(ctx).pop(s),
                    builder: (context, focused) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: focused
                            ? colors.brandPrimary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Season $s',
                        style: GoogleFonts.outfit(
                          color: focused ? Colors.white : colors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _season = picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = _seriesInfo?.info.name ?? widget.series.name;
    final cover = _seriesInfo?.info.cover ?? widget.series.cover;
    final plot = _seriesInfo?.info.plot ?? widget.series.plot;
    final genre = _seriesInfo?.info.genre ?? widget.series.genre;
    final releaseDate =
        _seriesInfo?.info.releaseDate ?? widget.series.releaseDate;
    final year = releaseDate.length >= 4
        ? releaseDate.substring(0, 4)
        : releaseDate;

    final userPrefs = context.watch<UserPrefsProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final content = context.read<ContentProvider>();
    final isArabic = userPrefs.locale == 'ar';

    final seasons = _seriesInfo != null
        ? (_seriesInfo!.episodes.keys.toList()..sort())
        : <int>[];
    final episodeCount = _seriesInfo?.episodes[_season]?.length ?? 0;

    // The button opens a picker rather than downloading anything directly,
    // so it just needs *some* episode in this season to be downloadable —
    // the picker itself sorts out which individual ones are eligible.
    final canDownload = (_seriesInfo?.episodes[_season] ?? const []).any(
      (ep) => DownloadsProvider.isDownloadable(_urlFor(ep)),
    );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // No ImageFiltered blur here — see the identical note in
          // TvMovieDetailScreen for why it was removed.
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
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Poster beside its info, not underneath it —
                        // see the class doc comment. ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                // A quarter of the previous 380px column.
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
                                    style: GoogleFonts.outfit(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (year.isNotEmpty)
                                        Text(
                                          year,
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            color: colors.ink.withValues(
                                              alpha: 0.6,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        seasons.length == 1
                                            ? (isArabic
                                                  ? 'موسم واحد'
                                                  : '1 Season')
                                            : (isArabic
                                                  ? '${seasons.length} مواسم'
                                                  : '${seasons.length} Seasons'),
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          color: colors.ink.withValues(
                                            alpha: 0.6,
                                          ),
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
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              color: colors.ink.withValues(
                                                alpha: 0.6,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (plot.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      plot,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        fontSize: 14.5,
                                        height: 1.45,
                                        color: colors.ink.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
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
                                        onTap: seasons.isEmpty
                                            ? null
                                            : _playResumeOrFirst,
                                      ),
                                      const SizedBox(width: 14),
                                      TvDetailActionButton(
                                        icon: Icon(
                                          userPrefs.isFavorite(
                                                widget.series.seriesId
                                                    .toString(),
                                              )
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          color:
                                              userPrefs.isFavorite(
                                                widget.series.seriesId
                                                    .toString(),
                                              )
                                              ? colors.brandPrimary
                                              : Colors.black,
                                          size: 22,
                                        ),
                                        onTap: () => userPrefs.toggleFavorite(
                                          id: widget.series.seriesId.toString(),
                                          title: widget.series.name,
                                          posterUrl: widget.series.cover,
                                          type: MediaType.series,
                                          rawData: {
                                            'series_id': widget.series.seriesId,
                                            'name': widget.series.name,
                                            'cover': widget.series.cover,
                                            'category_id':
                                                widget.series.categoryId,
                                            'plot': widget.series.plot,
                                            'cast': widget.series.cast,
                                            'director': widget.series.director,
                                            'genre': widget.series.genre,
                                            'releaseDate':
                                                widget.series.releaseDate,
                                            'rating': widget.series.rating,
                                            'last_modified':
                                                widget.series.lastModified,
                                          },
                                        ),
                                      ),
                                      if (canDownload) ...[
                                        const SizedBox(width: 14),
                                        TvDetailActionButton(
                                          icon: const Icon(
                                            Icons.download_rounded,
                                            color: Colors.black,
                                            size: 22,
                                          ),
                                          onTap: _pickEpisodesToDownload,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // ── Episodes ──
                        Row(
                          children: [
                            Text(
                              isArabic ? 'الحلقات' : 'EPISODES',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                                letterSpacing: 1.2,
                                color: colors.ink,
                              ),
                            ),
                            const Spacer(),
                            if (seasons.length > 1)
                              _SeasonPickerButton(
                                season: _season,
                                episodeCount: episodeCount,
                                onTap: () => _pickSeason(seasons),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _EpisodesList(
                            episodes:
                                _seriesInfo?.episodes[_season] ?? const [],
                            userPrefs: userPrefs,
                            downloads: downloads,
                            content: content,
                            isArabic: isArabic,
                            onPlay: _playEpisode,
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
}

class _SeasonPickerButton extends StatelessWidget {
  final int season;
  final int episodeCount;
  final VoidCallback onTap;

  const _SeasonPickerButton({
    required this.season,
    required this.episodeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TvFocusScope(
      onTap: onTap,
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: focused
              ? colors.brandPrimary
              : colors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Season $season · $episodeCount ep',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: focused ? Colors.white : colors.ink,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: focused ? Colors.white : colors.ink,
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodesList extends StatelessWidget {
  final List<XtreamEpisode> episodes;
  final UserPrefsProvider userPrefs;
  final DownloadsProvider downloads;
  final ContentProvider content;
  final bool isArabic;
  final void Function(XtreamEpisode) onPlay;

  const _EpisodesList({
    required this.episodes,
    required this.userPrefs,
    required this.downloads,
    required this.content,
    required this.isArabic,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (episodes.isEmpty) {
      return Center(
        child: Text(
          isArabic ? 'لا توجد حلقات.' : 'No episodes.',
          style: TextStyle(color: colors.ink.withValues(alpha: 0.4)),
        ),
      );
    }
    final sorted = List<XtreamEpisode>.from(episodes)
      ..sort((a, b) => a.episodeNum.compareTo(b.episodeNum));

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final ep = sorted[index];
        final position = userPrefs.getHistoryPosition(ep.id);
        return TvFocusScope(
          onTap: () => onPlay(ep),
          builder: (context, focused) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: focused
                    ? colors.brandAccent.withValues(alpha: 0.18)
                    : colors.surface.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused ? colors.brandAccent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${ep.episodeNum}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: colors.ink.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ep.title.isNotEmpty
                              ? ep.title
                              : (isArabic
                                    ? 'الحلقة ${ep.episodeNum}'
                                    : 'Episode ${ep.episodeNum}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.ink,
                          ),
                        ),
                        if (position > 0)
                          Text(
                            isArabic
                                ? 'شوهد ${position ~/ 60} د'
                                : 'Watched ${position ~/ 60}m',
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              color: colors.brandAccent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Multi-select episode picker shown by the series Download button.
///
/// Pops a `List<XtreamEpisode>` of everything ticked, or null if cancelled.
/// Episodes already downloaded / already in the download queue are listed
/// but not selectable — there is nothing useful to do with them here, and
/// silently re-queueing them would be worse than saying so.
class _EpisodeDownloadPicker extends StatefulWidget {
  final List<XtreamEpisode> episodes;
  final int season;
  final DownloadsProvider downloads;
  final bool isArabic;
  final bool Function(XtreamEpisode) isDownloadable;

  const _EpisodeDownloadPicker({
    required this.episodes,
    required this.season,
    required this.downloads,
    required this.isArabic,
    required this.isDownloadable,
  });

  @override
  State<_EpisodeDownloadPicker> createState() => _EpisodeDownloadPickerState();
}

class _EpisodeDownloadPickerState extends State<_EpisodeDownloadPicker> {
  final Set<String> _selected = {};

  bool _isEligible(XtreamEpisode ep) =>
      !widget.downloads.isDownloaded(ep.id) &&
      !widget.downloads.isDownloading(ep.id) &&
      widget.isDownloadable(ep);

  String _statusLabel(XtreamEpisode ep) {
    if (widget.downloads.isDownloaded(ep.id)) {
      return widget.isArabic ? 'تم التنزيل' : 'Downloaded';
    }
    if (widget.downloads.isDownloading(ep.id)) {
      return widget.isArabic ? 'قيد التنزيل' : 'Downloading';
    }
    return widget.isArabic ? 'غير متاح' : 'Unavailable';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isArabic = widget.isArabic;
    final eligible = widget.episodes.where(_isEligible).toList();

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic
                    ? 'تنزيل حلقات — الموسم ${widget.season}'
                    : 'Download episodes — Season ${widget.season}',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.episodes.length,
                  itemBuilder: (context, index) {
                    final ep = widget.episodes[index];
                    final eligibleHere = _isEligible(ep);
                    final checked = _selected.contains(ep.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TvFocusScope(
                        autofocus: index == 0,
                        onTap: eligibleHere
                            ? () => setState(() {
                                if (!_selected.remove(ep.id)) {
                                  _selected.add(ep.id);
                                }
                              })
                            : null,
                        builder: (context, focused) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: focused
                                ? colors.brandPrimary.withValues(alpha: 0.25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: focused
                                  ? colors.brandAccent
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                checked
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                size: 18,
                                color: !eligibleHere
                                    ? colors.ink.withValues(alpha: 0.25)
                                    : (checked
                                          ? colors.brandAccent
                                          : colors.ink.withValues(alpha: 0.6)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  ep.title.isNotEmpty
                                      ? '${ep.episodeNum}. ${ep.title}'
                                      : (isArabic
                                            ? 'الحلقة ${ep.episodeNum}'
                                            : 'Episode ${ep.episodeNum}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12.5,
                                    color: eligibleHere
                                        ? colors.ink
                                        : colors.ink.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                              if (!eligibleHere)
                                Text(
                                  _statusLabel(ep),
                                  style: GoogleFonts.outfit(
                                    fontSize: 10.5,
                                    color: colors.ink.withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (eligible.isNotEmpty)
                    TvFocusScope(
                      onTap: () => setState(() {
                        if (_selected.length == eligible.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(eligible.map((e) => e.id));
                        }
                      }),
                      builder: (context, focused) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: focused
                              ? colors.brandPrimary
                              : Colors.transparent,
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          _selected.length == eligible.length
                              ? (isArabic ? 'إلغاء الكل' : 'Clear all')
                              : (isArabic ? 'تحديد الكل' : 'Select all'),
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: focused ? Colors.white : colors.ink,
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  TvFocusScope(
                    onTap: () => Navigator.of(context).pop(),
                    builder: (context, focused) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: focused
                            ? colors.brandPrimary
                            : Colors.transparent,
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        isArabic ? 'إلغاء' : 'Cancel',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: focused ? Colors.white : colors.ink,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TvFocusScope(
                    onTap: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                            widget.episodes
                                .where((e) => _selected.contains(e.id))
                                .toList(),
                          ),
                    builder: (context, focused) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: _selected.isEmpty
                            ? null
                            : LinearGradient(colors: colors.brandGradient),
                        color: _selected.isEmpty ? colors.surfaceMuted : null,
                        border: Border.all(
                          color: focused && _selected.isNotEmpty
                              ? colors.ink
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        _selected.isEmpty
                            ? (isArabic ? 'تنزيل' : 'Download')
                            : (isArabic
                                  ? 'تنزيل (${_selected.length})'
                                  : 'Download (${_selected.length})'),
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _selected.isEmpty
                              ? colors.ink.withValues(alpha: 0.4)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
