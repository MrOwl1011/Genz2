import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../models/download_item.dart';
import '../providers/downloads_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/resume_dialog.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  int _selectedTab = 0;

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mb = 1024 * 1024;
    if (bytes < mb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    final gb = 1024 * mb;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }

  Future<void> _openOffline(DownloadItem item) async {
    final userPrefs = context.read<UserPrefsProvider>();
    if (item.filePath == null) return;

    int position = userPrefs.getHistoryPosition(item.id);
    if (position > 30) {
      final result = await showResumeDialog(context, position);
      if (!mounted) return;
      if (result == false) {
        position = 0;
        userPrefs.clearHistoryPosition(item.id);
      }
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          streamUrl: Uri.file(item.filePath!).toString(),
          title: item.title,
          coverUrl: item.posterUrl,
          isLive: false,
          mediaId: item.id,
          mediaType: item.type,
          rawMediaData: item.rawData,
          initialPositionSeconds: position,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _confirmDelete(DownloadItem item, DownloadsProvider downloads) {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.error, width: 1.5),
        ),
        title: Text(
          'Delete Download?',
          style: GoogleFonts.outfit(color: colors.ink, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${item.title}"? This removes the file from your device.',
          style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.outfit(color: colors.ink)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              downloads.deleteDownload(item.id);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.outfit(color: colors.error, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final downloads = context.watch<DownloadsProvider>();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors.backgroundGradient,
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 24, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.ink, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        'DOWNLOADS',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: colors.ink,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Slanted Tabs
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _buildTab(0, 'Downloading (${downloads.downloading.length})'),
                    _buildTab(1, 'Downloads (${downloads.completedDownloads.length})'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: _selectedTab == 0
                    ? _buildDownloadingList(downloads, colors)
                    : _buildCompletedList(downloads, colors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index, String label) {
    final colors = context.colors;
    final isSelected = index == _selectedTab;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Transform(
        transform: Matrix4.skewX(-0.25),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: isSelected ? colors.brandPrimary : colors.surfaceMuted,
          ),
          alignment: Alignment.center,
          child: Transform(
            transform: Matrix4.skewX(0.25),
            child: Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? Colors.white : colors.ink.withValues(alpha: 0.7),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(String message, AppColors colors) {
    return Center(
      child: Text(
        message,
        style: GoogleFonts.outfit(color: colors.ink.withValues(alpha: 0.38), fontSize: 16),
      ),
    );
  }

  Widget _buildDownloadingList(DownloadsProvider downloads, AppColors colors) {
    final items = downloads.downloading;
    if (items.isEmpty) return _buildEmpty('Nothing is downloading right now.', colors);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildThumb(item, colors),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: colors.ink, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: item.totalBytes > 0 ? item.progress : null,
                        minHeight: 6,
                        backgroundColor: colors.ink.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(colors.brandPrimary),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.totalBytes > 0
                          ? '${_formatBytes(item.downloadedBytes)} / ${_formatBytes(item.totalBytes)}'
                          : _formatBytes(item.downloadedBytes),
                      style: GoogleFonts.outfit(
                        color: colors.ink.withValues(alpha: 0.54),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colors.error),
                tooltip: 'Cancel',
                onPressed: () => downloads.cancelDownload(item.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompletedList(DownloadsProvider downloads, AppColors colors) {
    final items = downloads.completedDownloads;
    if (items.isEmpty) return _buildEmpty('No downloads yet.', colors);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () => _openOffline(item),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _buildThumb(item, colors),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(color: colors.ink, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatBytes(item.totalBytes),
                        style: GoogleFonts.outfit(
                          color: colors.ink.withValues(alpha: 0.54),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: colors.ink.withValues(alpha: 0.7)),
                  tooltip: 'Redownload',
                  onPressed: () => downloads.redownload(item.id),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: colors.error),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(item, downloads),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumb(DownloadItem item, AppColors colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: item.posterUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: item.posterUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  color: colors.surface,
                  child: Icon(Icons.movie, color: colors.ink.withValues(alpha: 0.24)),
                ),
              )
            : Container(
                color: colors.surface,
                child: Icon(Icons.movie, color: colors.ink.withValues(alpha: 0.24)),
              ),
      ),
    );
  }
}
