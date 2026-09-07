import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/playlist_model.dart';
import '../models/xtream_models.dart';
import '../providers/auth_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import 'movie_details_screen.dart';
import 'series_details_screen.dart';

/// Read-only watch history for a single saved playlist. Reachable from the
/// Saved Playlists screen — items only open the player/details when the
/// viewed playlist is the currently active/authenticated session, since
/// ContentProvider only ever holds one server's credentials at a time.
class PlaylistHistoryScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistHistoryScreen({super.key, required this.playlist});

  @override
  State<PlaylistHistoryScreen> createState() => _PlaylistHistoryScreenState();
}

class _PlaylistHistoryScreenState extends State<PlaylistHistoryScreen> {
  List<HistoryItem> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final userPrefs = Provider.of<UserPrefsProvider>(context, listen: false);
    final items = await userPrefs.peekHistoryForPlaylist(widget.playlist.id);
    if (mounted) {
      setState(() {
        _history = items;
        _isLoading = false;
      });
    }
  }

  bool get _isActivePlaylist {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return auth.isAuthenticated && auth.playlistId == widget.playlist.id;
  }

  void _onItemTap(HistoryItem item) {
    if (!_isActivePlaylist) {
      final colors = context.colors;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: colors.surfaceMuted,
          content: Text(
            'Log in to "${widget.playlist.playlistName}" to resume watching this.',
            style: AppType.sans(color: colors.ink),
          ),
        ),
      );
      return;
    }

    if (item.type == MediaType.movie) {
      final movie = XtreamVodStream.fromJson(item.rawData);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MovieDetailsScreen(movie: movie)),
      );
    } else if (item.type == MediaType.series) {
      final series = XtreamSeries(
        seriesId: item.rawData['series_id'] ?? int.tryParse(item.id) ?? 0,
        name: item.rawData['series_name'] ?? item.title,
        cover: item.rawData['series_cover'] ?? item.posterUrl,
        categoryId: item.rawData['category_id']?.toString() ?? '',
        lastModified:
            int.tryParse(item.rawData['last_modified']?.toString() ?? '0') ?? 0,
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SeriesDetailsScreen(series: series)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userPrefs = context.watch<UserPrefsProvider>();
    final isArabic = userPrefs.locale == 'ar';
    final colors = context.colors;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.backgroundGradient,
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 24, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: colors.ink,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        widget.playlist.playlistName.toUpperCase(),
                        style: AppType.sans(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: colors.ink,
                          letterSpacing: 1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 24, 0),
                child: Text(
                  isArabic ? 'سجل المشاهدة' : 'Watch History',
                  style: AppType.sans(
                    color: colors.ink.withValues(alpha: 0.38),
                    fontSize: 13,
                  ),
                ),
              ),
              if (!_isActivePlaylist)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.ink.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.ink.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: colors.ink.withValues(alpha: 0.38),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isArabic
                                ? 'سجل عرض فقط. سجل الدخول لهذه القائمة للمتابعة من هنا.'
                                : 'View-only. Log in to this playlist to resume from here.',
                            style: AppType.sans(
                              color: colors.ink.withValues(alpha: 0.54),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(isArabic)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isArabic) {
    final colors = context.colors;
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(
        child: Text(
          isArabic
              ? 'لا يوجد سجل مشاهدة لهذه القائمة.'
              : 'No watch history for this playlist.',
          style: AppType.sans(
            color: colors.ink.withValues(alpha: 0.38),
            fontSize: 15,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _history.length,
      itemBuilder: (context, index) => _buildHistoryTile(_history[index]),
    );
  }

  Widget _buildHistoryTile(HistoryItem item) {
    final colors = context.colors;
    final progress = item.durationMilliseconds > 0
        ? (item.positionMilliseconds / item.durationMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return Opacity(
      opacity: _isActivePlaylist ? 1.0 : 0.6,
      child: GestureDetector(
        onTap: () => _onItemTap(item),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 84,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: item.posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.posterUrl,
                        width: 64,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(
                          width: 64,
                          color: colors.surfaceMuted,
                          child: Icon(
                            Icons.movie,
                            color: colors.ink.withValues(alpha: 0.24),
                          ),
                        ),
                      )
                    : Container(
                        width: 64,
                        color: colors.surfaceMuted,
                        child: Icon(
                          Icons.movie,
                          color: colors.ink.withValues(alpha: 0.24),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 12,
                    bottom: 12,
                    right: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(
                          color: colors.ink,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.lastWatched.day}/${item.lastWatched.month}/${item.lastWatched.year}',
                        style: AppType.sans(
                          color: colors.ink.withValues(alpha: 0.38),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (item.durationMilliseconds > 0)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: colors.ink.withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colors.brandPrimary,
                            ),
                            minHeight: 3,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_isActivePlaylist)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: colors.ink.withValues(alpha: 0.38),
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
