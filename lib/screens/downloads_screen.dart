import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../models/download_item.dart';
import '../providers/downloads_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/state_view.dart';
import '../widgets/dialog_buttons.dart';
import '../widgets/resume_dialog.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  int _selectedTab = 0;
  // Ids currently awaiting DownloadsProvider.pauseDownload's server-support
  // check — that can take several seconds (see the comment there), so the
  // pause button shows a spinner instead of looking frozen/unresponsive.
  final Set<String> _pausingIds = {};

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mb = 1024 * 1024;
    if (bytes < mb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    final gb = 1024 * mb;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }

  static String _formatSpeed(double mbPerSecond) {
    if (mbPerSecond >= 1) return '${mbPerSecond.toStringAsFixed(1)} MB/s';
    return '${(mbPerSecond * 1024).toStringAsFixed(0)} KB/s';
  }

  Future<void> _openOffline(DownloadItem item) async {
    final userPrefs = context.read<UserPrefsProvider>();
    if (item.filePath == null) return;

    int position = userPrefs.getHistoryPosition(item.id);
    if (position > 30) {
      final isArabic = userPrefs.locale == 'ar';
      final season = item.rawData['season'];
      final episodeNum = item.rawData['episode_num'];
      final episodeLabel =
          item.type == MediaType.series && season != null && episodeNum != null
          ? (isArabic
                ? 'الموسم $season · الحلقة $episodeNum'
                : 'Season $season · Episode $episodeNum')
          : null;
      final result = await showResumeDialog(
        context,
        position,
        episodeLabel: episodeLabel,
      );
      if (!mounted) return;
      if (result == null) {
        return; // dismissed via X or outside tap — cancelled, don't open the player
      }
      if (result == false) {
        position = 0;
        userPrefs.clearHistoryPosition(item.id);
      }
    }

    if (!mounted) return;
    Navigator.of(context)
        .push(
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
        )
        .then((_) => setState(() {}));
  }

  void _confirmDelete(DownloadItem item, DownloadsProvider downloads) {
    final colors = context.colors;
    final isArabic = context.read<UserPrefsProvider>().locale == 'ar';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.error, width: 1.5),
        ),
        title: Text(
          isArabic ? 'حذف التنزيل؟' : 'Delete Download?',
          style: GoogleFonts.archivo(
            color: colors.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          isArabic
              ? 'هل أنت متأكد أنك تريد حذف "${item.title}"؟ سيتم حذف الملف من جهازك.'
              : 'Are you sure you want to delete "${item.title}"? This removes the file from your device.',
          style: GoogleFonts.archivo(color: colors.ink.withValues(alpha: 0.7)),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          DialogSecondaryButton(
            label: isArabic ? 'إلغاء' : 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          DialogPrimaryButton(
            label: isArabic ? 'حذف' : 'Delete',
            color: colors.error,
            onPressed: () {
              Navigator.of(ctx).pop();
              downloads.deleteDownload(item.id);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final downloads = context.watch<DownloadsProvider>();
    final isArabic = context.watch<UserPrefsProvider>().locale == 'ar';

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
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: colors.ink,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        isArabic ? 'التنزيلات' : 'DOWNLOADS',
                        style: GoogleFonts.archivo(
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
                    _buildTab(
                      0,
                      isArabic
                          ? 'جارٍ التنزيل (${downloads.downloading.length})'
                          : 'Downloading (${downloads.downloading.length})',
                    ),
                    _buildTab(
                      1,
                      isArabic
                          ? 'التنزيلات (${downloads.completedDownloads.length + downloads.failedDownloads.length})'
                          : 'Downloads (${downloads.completedDownloads.length + downloads.failedDownloads.length})',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: _selectedTab == 0
                    ? _buildDownloadingList(downloads, colors, isArabic)
                    : _buildCompletedList(downloads, colors, isArabic),
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
              style: GoogleFonts.archivo(
                color: isSelected
                    ? Colors.white
                    : colors.ink.withValues(alpha: 0.7),
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
        style: GoogleFonts.archivo(
          color: colors.ink.withValues(alpha: 0.38),
          fontSize: 16,
        ),
      ),
    );
  }

  /// Pauses a download, surfacing the case where the server doesn't support
  /// resumable downloads — pausing there can't be resumed later, so it's
  /// left running instead of being torn down; see
  /// [DownloadsProvider.pauseDownload].
  Future<void> _pause(DownloadsProvider downloads, String id) async {
    setState(() => _pausingIds.add(id));
    final paused = await downloads.pauseDownload(id);
    if (!mounted) return;
    setState(() => _pausingIds.remove(id));
    if (!paused && mounted) {
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

  Widget _buildDownloadingList(
    DownloadsProvider downloads,
    AppColors colors,
    bool isArabic,
  ) {
    final items = downloads.downloading;
    if (items.isEmpty) {
      return _buildEmpty(
        isArabic
            ? 'لا يوجد تنزيل جارٍ الآن.'
            : 'Nothing is downloading right now.',
        colors,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isQueued = item.status == DownloadStatus.queued;
        final isPaused = item.status == DownloadStatus.paused;
        String statusLine;
        if (isQueued) {
          statusLine = isArabic ? 'في الانتظار' : 'Queued';
        } else if (isPaused) {
          statusLine =
              '${isArabic ? 'متوقف مؤقتاً' : 'Paused'} · ${_formatBytes(item.downloadedBytes)}'
              '${item.totalBytes > 0 ? ' / ${_formatBytes(item.totalBytes)}' : ''}';
        } else {
          final sizeText = item.totalBytes > 0
              ? '${_formatBytes(item.downloadedBytes)} / ${_formatBytes(item.totalBytes)}'
              : _formatBytes(item.downloadedBytes);
          final speedText = item.speedMBps > 0
              ? ' · ${_formatSpeed(item.speedMBps)}'
              : '';
          statusLine = '$sizeText$speedText';
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
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
                      style: GoogleFonts.archivo(
                        color: colors.ink,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: !isQueued && item.totalBytes > 0
                            ? item.progress
                            : null,
                        minHeight: 6,
                        backgroundColor: colors.ink.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isPaused
                              ? colors.ink.withValues(alpha: 0.38)
                              : colors.brandPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusLine,
                      style: GoogleFonts.archivo(
                        color: colors.ink.withValues(alpha: 0.54),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (!isQueued &&
                  DownloadsProvider.pauseSupported &&
                  _pausingIds.contains(item.id))
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else if (!isQueued && DownloadsProvider.pauseSupported)
                IconButton(
                  icon: Icon(
                    isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: colors.ink.withValues(alpha: 0.7),
                  ),
                  tooltip: isPaused
                      ? (isArabic ? 'استئناف' : 'Resume')
                      : (isArabic ? 'إيقاف مؤقت' : 'Pause'),
                  onPressed: () => isPaused
                      ? downloads.resumeDownload(item.id)
                      : _pause(downloads, item.id),
                ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: colors.error),
                tooltip: isArabic ? 'إلغاء' : 'Cancel',
                onPressed: () => downloads.cancelDownload(item.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompletedList(
    DownloadsProvider downloads,
    AppColors colors,
    bool isArabic,
  ) {
    // Failed transfers have nowhere else to appear once there's no
    // redownload button — surface them here (delete-only, no offline
    // playback) so they're never invisible/stuck.
    final items = [
      ...downloads.completedDownloads,
      ...downloads.failedDownloads,
    ];
    if (items.isEmpty) {
      return StateView(
        icon: Icons.download_done_rounded,
        title: isArabic ? 'لا توجد تنزيلات' : 'No downloads',
        message: isArabic
            ? 'اضغط على أيقونة التنزيل في أي فيلم أو حلقة لحفظه هنا.'
            : 'Tap the download icon on any title to keep it here for '
                  'offline viewing.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isFailed = item.status == DownloadStatus.failed;
        return GestureDetector(
          onTap: isFailed ? null : () => _openOffline(item),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
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
                        style: GoogleFonts.archivo(
                          color: colors.ink,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isFailed
                            ? (isArabic ? 'فشل التنزيل' : 'Download failed')
                            : _formatBytes(item.totalBytes),
                        style: GoogleFonts.archivo(
                          color: isFailed
                              ? colors.error
                              : colors.ink.withValues(alpha: 0.54),
                          fontSize: 12,
                          fontWeight: isFailed
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: colors.error),
                  tooltip: isArabic ? 'حذف' : 'Delete',
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
                  child: Icon(
                    Icons.movie,
                    color: colors.ink.withValues(alpha: 0.24),
                  ),
                ),
              )
            : Container(
                color: colors.surface,
                child: Icon(
                  Icons.movie,
                  color: colors.ink.withValues(alpha: 0.24),
                ),
              ),
      ),
    );
  }
}
