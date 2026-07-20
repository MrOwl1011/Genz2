import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/user_prefs_provider.dart';
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
  /// Shows a dialog if saved position > 30 seconds.
  void _playEpisode(XtreamEpisode episode) async {
    final content = context.read<ContentProvider>();
    final userPrefs = context.read<UserPrefsProvider>();
    final url = episode.streamUrl(content.baseUrl, content.username, content.password);

    int position = userPrefs.getHistoryPosition(episode.id);

    // Show resume dialog if position > 30 seconds
    if (position > 30) {
      final result = await showResumeDialog(context, position);
      if (!mounted) return;
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
            'url': ep.streamUrl(content.baseUrl, content.username, content.password),
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

    return Scaffold(
      backgroundColor: const Color(0xFF0C0002),
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
                            Container(color: Colors.grey[900]),
                      )
                    : Container(color: Colors.grey[900]),
                // Gradient to blend poster into black background
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x88000000),
                        Color(0xFF0C0002),
                      ],
                      stops: [0.0, 0.7, 1.0],
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
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Play/Like/Download Buttons (Overlapping top edge)
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
                                color: isFav ? const Color(0xFFE50914) : Colors.black,
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
                          GestureDetector(
                            onTap: () => _playResumeOrFirst(),
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE50914),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.download_rounded, color: Colors.black),
                              onPressed: () {}, // Download button
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
                        ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
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
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (releaseDate.isNotEmpty)
                                            Text(
                                              releaseDate,
                                              style: GoogleFonts.outfit(color: Colors.white70),
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
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                if (plot.isNotEmpty)
                                  Text(
                                    plot,
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFFE50914), // Red description per user request
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
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (director.isNotEmpty) ...[
                                  Text(
                                    director,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white70,
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
    final List<Widget> items = [];
    final sortedSeasons = _seriesInfo!.episodes.keys.toList()..sort();
    final userPrefs = context.read<UserPrefsProvider>(); // read history for progress

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
              color: const Color(0xFFE50914),
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
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  ep.episodeNum.toString(),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            title: Text(
              ep.title.isNotEmpty ? ep.title : 'Episode ${ep.episodeNum}',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: position > 0 
                ? Text('Watched ${position ~/ 60}m', style: const TextStyle(color: Color(0xFFE50914), fontSize: 12))
                : null,
            trailing: const Icon(Icons.play_circle_fill_rounded, color: Colors.white54),
            onTap: () => _playEpisode(ep),
          ),
        );
      }
    }
    return items;
  }
}
