import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/xtream_models.dart';
import '../providers/content_provider.dart';
import '../providers/user_prefs_provider.dart';
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
  /// Shows a dialog if saved position > 30 seconds.
  void _openPlayer(BuildContext context) async {
    final content = context.read<ContentProvider>();
    final userPrefs = context.read<UserPrefsProvider>();
    final url = widget.movie.streamUrl(content.baseUrl, content.username, content.password);

    int position = userPrefs.getHistoryPosition(widget.movie.streamId.toString());

    // Show resume dialog if position > 30 seconds
    if (position > 30) {
      final result = await showResumeDialog(context, position);
      if (!mounted) return;
      if (result == false) {
        position = 0; // User chose "Start Over"
        userPrefs.clearHistoryPosition(widget.movie.streamId.toString());
      }
      // result == true or null means resume from saved position
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: url,
          title: widget.movie.name,
          coverUrl: widget.movie.streamIcon,
          isLive: false,
          mediaId: widget.movie.streamId.toString(),
          mediaType: MediaType.movie,
          rawMediaData: widget.movie.toJson(),
          initialPositionSeconds: position,
        ),
      ),
    ).then((_) {
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
    final releaseDate = _vodInfo?.movieData.releaseDate ?? widget.movie.releaseDate;
    final duration = _vodInfo?.duration ?? '';

    final userPrefs = context.watch<UserPrefsProvider>();
    final isFav = userPrefs.isFavorite(widget.movie.streamId.toString());

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
          
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.video_library_rounded, color: Colors.white, size: 28),
              onPressed: () {},
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
                                color: isFav ? const Color(0xFFE50914) : Colors.black,
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
                                    'container_extension': widget.movie.containerExtension,
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
                          GestureDetector(
                            onTap: () => _openPlayer(context),
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
                                          if (duration.isNotEmpty)
                                            Text(
                                              duration,
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
}
