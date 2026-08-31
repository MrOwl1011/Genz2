import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_item.dart';
import '../services/player_backend.dart' show kIptvUserAgent;
import 'user_prefs_provider.dart' show MediaType;

/// Manages on-device downloads (movies + series episodes), scoped per
/// playlist/account so different users' downloads never mix — mirrors the
/// same `downloads_<playlistId>` partitioning [UserPrefsProvider] already
/// uses for favorites/history, and stores files under a matching per-playlist
/// subfolder on disk.
///
/// Transfers run on top of `background_downloader`, which hands them to the
/// OS's own background transfer APIs (`URLSession` on iOS, a foreground
/// service on Android), so a download keeps going after the app is
/// backgrounded or the process is killed, and is reconciled against
/// [FileDownloader.database] the next time this provider loads. New
/// downloads are handed to a single-lane [MemoryTaskQueue] rather than
/// enqueued directly, so starting one never cancels another that's already
/// in flight — it queues behind it instead.
class DownloadsProvider extends ChangeNotifier {
  static bool _pluginStarted = false;

  /// Whether the pause/resume UI should be offered at all. background_downloader's
  /// pause support depends on the plugin correctly learning, from the
  /// server's response, whether a transfer can be resumed — on Android that
  /// has worked reliably; on iOS it has repeatedly proven unreliable (a
  /// genuinely pausable transfer still gets reported as unpausable), even
  /// after working around the most likely causes. Rather than continue to
  /// offer a control that unpredictably fails on iOS, pause/resume is
  /// Android-only; iOS downloads can still be canceled, just not paused.
  static bool get pauseSupported => !Platform.isIOS;

  String _playlistId = '';
  List<DownloadItem> _downloads = [];

  final MemoryTaskQueue _queue = MemoryTaskQueue()..maxConcurrent = 1;
  StreamSubscription<TaskUpdate>? _updatesSub;

  DownloadsProvider() {
    _initPlugin();
  }

  void _initPlugin() {
    if (_pluginStarted) return;
    _pluginStarted = true;
    // Android supports a real, live-updating progress bar in the download
    // notification. iOS does not — a plain local notification there can't
    // show a progress bar or have its body text refreshed in place (the
    // plugin's own {progress} placeholder is documented as ignored on iOS),
    // so the notification just sits there showing stale text, which reads
    // as broken. Rather than ship something that looks broken on iOS,
    // download notifications — and the permission prompt for them — are
    // Android-only; iOS users still see full in-app progress on the
    // Downloads screen and the download buttons themselves.
    if (!Platform.isIOS) {
      FileDownloader().configureNotification(
        running: const TaskNotification(
          'Downloading {displayName}',
          '{progress} · {networkSpeed}',
        ),
        paused: const TaskNotification('Paused {displayName}', '{progress}'),
        complete: const TaskNotification('Download complete', '{displayName}'),
        error: const TaskNotification('Download failed', '{displayName}'),
        progressBar: true,
      );
      unawaited(
        FileDownloader().permissions.request(PermissionType.notifications),
      );
    }
    FileDownloader().addTaskQueue(_queue);
    _updatesSub = FileDownloader().updates.listen(_handleUpdate);
    // Registers the listener above before kicking off the plugin's own
    // restart recovery (re-enqueueing tasks that were still running when the
    // app was last killed, marking tasks complete if their file already
    // exists) so none of those recovery events are missed.
    unawaited(FileDownloader().start());
  }

  @override
  void dispose() {
    _updatesSub?.cancel();
    super.dispose();
  }

  List<DownloadItem> get downloading => _downloads
      .where(
        (d) =>
            d.status == DownloadStatus.queued ||
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.paused,
      )
      .toList();

  List<DownloadItem> get completedDownloads =>
      _downloads.where((d) => d.status == DownloadStatus.completed).toList();

  List<DownloadItem> get failedDownloads =>
      _downloads.where((d) => d.status == DownloadStatus.failed).toList();

  bool isDownloaded(String id) =>
      _downloads.any((d) => d.id == id && d.status == DownloadStatus.completed);

  /// True while the item is anywhere in the pipeline — queued, actively
  /// transferring, or paused. Screens use this to switch away from the plain
  /// "download" button.
  bool isDownloading(String id) => _downloads.any(
    (d) =>
        d.id == id &&
        (d.status == DownloadStatus.queued ||
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.paused),
  );

  bool isPaused(String id) =>
      _downloads.any((d) => d.id == id && d.status == DownloadStatus.paused);

  bool isQueued(String id) =>
      _downloads.any((d) => d.id == id && d.status == DownloadStatus.queued);

  DownloadItem? itemFor(String id) {
    try {
      return _downloads.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  // ─── Task id / group helpers ───────────────────────────────────────────────
  //
  // A task id encodes the owning playlist so updates arriving from the
  // plugin's global stream can always be routed back to the right playlist's
  // in-memory list (or ignored if it's not the active one — see
  // [_handleUpdate]) without a separate lookup table.

  String _taskId(String playlistId, String id) => '$playlistId::$id';

  (String playlistId, String id)? _parseTaskId(String taskId) {
    final sep = taskId.indexOf('::');
    if (sep == -1) return null;
    return (taskId.substring(0, sep), taskId.substring(sep + 2));
  }

  // ─── Playlist Scoping ──────────────────────────────────────────────────────

  Future<void> setPlaylistId(String id) async {
    if (id.isEmpty || id == _playlistId) return;
    _playlistId = id;
    await _load();
  }

  Future<void> reset() async {
    _playlistId = '';
    _downloads = [];
    notifyListeners();
  }

  Future<void> deletePlaylistData(String playlistId) async {
    if (playlistId.isEmpty) return;

    await _cancelAllForPlaylist(playlistId);

    if (playlistId == _playlistId) {
      _downloads = [];
      notifyListeners();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('downloads_$playlistId');
    try {
      final dir = await _dirFor(playlistId);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _cancelAllForPlaylist(String playlistId) async {
    _queue.removeTasksWithGroup(playlistId);
    try {
      final tasks = await FileDownloader().allTasks(
        group: playlistId,
        allGroups: false,
      );
      if (tasks.isNotEmpty) {
        await FileDownloader().cancelTasksWithIds(tasks.map((t) => t.taskId));
      }
      final records = await FileDownloader().database.allRecords(
        group: playlistId,
      );
      await FileDownloader().database.deleteRecordsWithIds(
        records.map((r) => r.taskId),
      );
    } catch (_) {}
  }

  Future<void> migratePlaylistData(String oldId, String newId) async {
    if (oldId.isEmpty || newId.isEmpty || oldId == newId) return;
    final prefs = await SharedPreferences.getInstance();
    final oldRaw = prefs.getStringList('downloads_$oldId');
    if (oldRaw != null) {
      await prefs.setStringList('downloads_$newId', oldRaw);
      await prefs.remove('downloads_$oldId');
    }
    try {
      final oldDir = await _dirFor(oldId);
      if (await oldDir.exists()) {
        final newDir = await _dirFor(newId);
        if (await newDir.exists()) await newDir.delete(recursive: true);
        await oldDir.rename(newDir.path);
      }
    } catch (_) {}

    if (_playlistId == newId) await _load();
  }

  Future<Directory> _dirFor(String playlistId) async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/downloads/$playlistId');
  }

  Future<Directory> _ensureDirFor(String playlistId) async {
    final dir = await _dirFor(playlistId);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _load() async {
    if (_playlistId.isEmpty) {
      _downloads = [];
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('downloads_$_playlistId');
    if (raw == null) {
      _downloads = [];
    } else {
      _downloads = raw
          .map((e) => DownloadItem.fromJson(jsonDecode(e)))
          .toList();
      for (final d in _downloads) {
        if (d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued ||
            d.status == DownloadStatus.paused) {
          await _reconcileItem(d);
        }
      }
    }
    notifyListeners();
    await _persist();
  }

  /// Brings one persisted in-progress item back in sync with reality after a
  /// cold start, using the plugin's own persistent record for its task
  /// (already reconciled by [FileDownloader.start] before this runs — killed
  /// tasks re-enqueued, finished-while-killed tasks marked complete).
  ///
  /// An item that was still only [DownloadStatus.queued] — sitting in our
  /// in-memory [MemoryTaskQueue] and never actually handed to the native
  /// downloader — has no record at all after a full process kill, since that
  /// queue isn't itself persisted; it's marked failed so the user can retry.
  Future<void> _reconcileItem(DownloadItem item) async {
    try {
      final record = await FileDownloader().database.recordForId(
        _taskId(_playlistId, item.id),
      );
      if (record == null) {
        item.status = DownloadStatus.failed;
        item.speedMBps = 0;
        return;
      }
      switch (record.status) {
        case TaskStatus.complete:
          item.status = DownloadStatus.completed;
          await _fillInSizeFromDisk(item);
        case TaskStatus.enqueued:
        case TaskStatus.running:
        case TaskStatus.waitingToRetry:
          item.status = DownloadStatus.downloading;
        case TaskStatus.paused:
          item.status = DownloadStatus.paused;
        case TaskStatus.failed:
        case TaskStatus.notFound:
        case TaskStatus.canceled:
          item.status = DownloadStatus.failed;
      }
      item.speedMBps = 0;
    } catch (_) {
      item.status = DownloadStatus.failed;
      item.speedMBps = 0;
    }
  }

  Future<void> _fillInSizeFromDisk(DownloadItem item) async {
    final path = item.filePath;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) {
        final len = await f.length();
        item.totalBytes = len;
        item.downloadedBytes = len;
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    if (_playlistId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'downloads_$_playlistId',
      _downloads.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  // ─── Live updates from the plugin ──────────────────────────────────────────

  void _handleUpdate(TaskUpdate update) {
    final parsed = _parseTaskId(update.task.taskId);
    if (parsed == null) return;
    final (playlistId, id) = parsed;
    // Not the active account right now — its own next _load() will
    // reconcile against the plugin's database, so there's nothing to do
    // with a live event for it here.
    if (playlistId != _playlistId) return;
    final item = itemFor(id);
    if (item == null) return;

    if (update is TaskStatusUpdate) {
      switch (update.status) {
        case TaskStatus.enqueued:
        case TaskStatus.running:
        case TaskStatus.waitingToRetry:
          item.status = DownloadStatus.downloading;
        case TaskStatus.paused:
          item.status = DownloadStatus.paused;
          item.speedMBps = 0;
        case TaskStatus.complete:
          item.status = DownloadStatus.completed;
          item.speedMBps = 0;
          unawaited(
            _fillInSizeFromDisk(item).then((_) {
              notifyListeners();
              _persist();
            }),
          );
        case TaskStatus.failed:
        case TaskStatus.notFound:
          item.status = DownloadStatus.failed;
          item.speedMBps = 0;
        case TaskStatus.canceled:
          _downloads.removeWhere((d) => d.id == id);
      }
      notifyListeners();
      unawaited(_persist());
    } else if (update is TaskProgressUpdate) {
      if (update.hasExpectedFileSize && update.expectedFileSize > 0) {
        item.totalBytes = update.expectedFileSize;
      }
      if (item.totalBytes > 0 && update.progress >= 0) {
        item.downloadedBytes = (update.progress * item.totalBytes).round();
      }
      item.speedMBps = update.hasNetworkSpeed ? update.networkSpeed : 0;
      notifyListeners();
    }
  }

  // ─── Transfers ──────────────────────────────────────────────────────────────

  /// HLS manifests (`.m3u8`) reference separate segment files — often via
  /// paths relative to the original server — so saving the manifest text
  /// itself as "the download" doesn't produce anything playable offline.
  /// Screens should use this to hide/disable the download action for such
  /// sources rather than let it silently produce a broken file.
  static bool isDownloadable(String sourceUrl) {
    final path =
        Uri.tryParse(sourceUrl)?.path.toLowerCase() ?? sourceUrl.toLowerCase();
    return !path.endsWith('.m3u8');
  }

  String _guessExtension(String url, Map<String, dynamic> rawData) {
    final containerExt = rawData['container_extension']?.toString();
    if (containerExt != null && containerExt.isNotEmpty) return containerExt;
    final uri = Uri.tryParse(url);
    final last = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : '';
    if (last.contains('.')) {
      final ext = last.split('.').last;
      if (ext.isNotEmpty && ext.length <= 5) return ext;
    }
    return 'mp4';
  }

  Future<void> startDownload({
    required String id,
    required String title,
    required String posterUrl,
    required MediaType type,
    required String sourceUrl,
    required Map<String, dynamic> rawData,
    Map<String, String> headers = const {'User-Agent': kIptvUserAgent},
  }) async {
    if (_playlistId.isEmpty) return;
    if (isDownloaded(id) || isDownloading(id)) return;
    // Safety net — screens should already be hiding the download action for
    // non-downloadable (HLS) sources, but don't silently write a useless
    // file if one slips through.
    if (!isDownloadable(sourceUrl)) return;

    final ownerPlaylistId = _playlistId;
    final dir = await _ensureDirFor(ownerPlaylistId);
    final ext = _guessExtension(sourceUrl, rawData);
    final filename = '$id.$ext';
    final path = '${dir.path}/$filename';

    _downloads.removeWhere((d) => d.id == id);
    final item = DownloadItem(
      id: id,
      title: title,
      posterUrl: posterUrl,
      type: type,
      sourceUrl: sourceUrl,
      rawData: rawData,
      createdAt: DateTime.now(),
      filePath: path,
    );
    _downloads.insert(0, item);
    notifyListeners();
    await _persist();

    final task = DownloadTask(
      taskId: _taskId(ownerPlaylistId, id),
      url: sourceUrl,
      filename: filename,
      directory: 'downloads/$ownerPlaylistId',
      baseDirectory: BaseDirectory.applicationDocuments,
      group: ownerPlaylistId,
      updates: Updates.statusAndProgress,
      headers: headers,
      allowPause: true,
      retries: 3,
      displayName: title,
    );
    _queue.add(task);
  }

  Future<void> cancelDownload(String id) async {
    final taskId = _taskId(_playlistId, id);
    _queue.removeTasksWithIds([taskId]);
    try {
      await FileDownloader().cancelTaskWithId(taskId);
      await FileDownloader().database.deleteRecordWithId(taskId);
    } catch (_) {}

    final item = itemFor(id);
    final path = item?.filePath;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _downloads.removeWhere((d) => d.id == id);
    notifyListeners();
    await _persist();
  }

  /// Pauses a running download. Returns false (without pausing) if the
  /// server for this source doesn't support resumable (ranged) downloads —
  /// pausing a non-resumable transfer can't be resumed later, so the plugin
  /// treats it as a failure and discards the partial file, which from the
  /// user's perspective looks exactly like the download being canceled.
  /// Checking first keeps the transfer running untouched instead.
  ///
  /// This deliberately does NOT use [FileDownloader.taskCanResume] — that
  /// answer lives only in the memory of the Dart isolate that originally
  /// enqueued the transfer, via a completer created at enqueue time. iOS
  /// suspends/restarts the Flutter engine far more readily than Android
  /// while a background `URLSession` transfer keeps running natively, so by
  /// the time the user comes back and taps pause, that isolate — and its
  /// completer — is very often long gone; the call then finds no pending
  /// answer and falls back to reporting "can't resume" even when the server
  /// would say otherwise. Probing the source URL directly here sidesteps
  /// that plugin-internal state entirely and gives the same, correct answer
  /// regardless of what the app's process has done since the download
  /// started.
  Future<bool> pauseDownload(String id) async {
    final item = itemFor(id);
    if (item == null) return false;
    final task = await FileDownloader().taskForId(_taskId(_playlistId, id));
    if (task is! DownloadTask) return false;
    if (!await _serverSupportsRangeRequests(item.sourceUrl)) return false;
    return FileDownloader().pause(task);
  }

  /// Directly probes whether [url] honors byte-range requests, by asking for
  /// just the first two bytes and checking for a `206 Partial Content`
  /// response (or an explicit `Accept-Ranges: bytes` header). Only reads
  /// headers — the connection is closed immediately after, so this doesn't
  /// wait on or download any of the body even if the server ignores the
  /// range and would otherwise have sent the whole file.
  Future<bool> _serverSupportsRangeRequests(String url) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = kIptvUserAgent;
      request.headers['Range'] = 'bytes=0-1';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 206 ||
          response.headers['accept-ranges']?.toLowerCase() == 'bytes';
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> resumeDownload(String id) async {
    final task = await FileDownloader().taskForId(_taskId(_playlistId, id));
    if (task is DownloadTask) {
      await FileDownloader().resume(task);
    }
  }

  /// Deletes a completed (or failed) download's file and removes it from the
  /// list — the originating download button reverts to its plain "download"
  /// state once this completes, since [isDownloaded]/[isDownloading] both
  /// become false.
  Future<void> deleteDownload(String id) async {
    final item = itemFor(id);
    if (item == null) return;

    if (item.status == DownloadStatus.queued ||
        item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.paused) {
      await cancelDownload(id);
      return;
    }

    final path = item.filePath;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _downloads.removeWhere((d) => d.id == id);
    notifyListeners();
    await _persist();
  }

  /// Re-fetches a download from scratch (used for a failed transfer, or to
  /// force a fresh copy of a completed one).
  Future<void> redownload(
    String id, {
    Map<String, String> headers = const {'User-Agent': kIptvUserAgent},
  }) async {
    final item = itemFor(id);
    if (item == null) return;
    final title = item.title;
    final posterUrl = item.posterUrl;
    final type = item.type;
    final sourceUrl = item.sourceUrl;
    final rawData = item.rawData;

    await deleteDownload(id);
    await startDownload(
      id: id,
      title: title,
      posterUrl: posterUrl,
      type: type,
      sourceUrl: sourceUrl,
      rawData: rawData,
      headers: headers,
    );
  }
}
