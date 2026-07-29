import 'dart:convert';
import 'dart:io';

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
/// There is no OS-level background download service in this app (no
/// WorkManager/URLSession wiring), so a transfer is a plain in-process HTTP
/// stream: it keeps going while the app is alive, but does not survive an
/// app kill or an account switch. Both cases cancel in-flight transfers and
/// discard the partial file rather than leaving a corrupt one behind.
class DownloadsProvider extends ChangeNotifier {
  String _playlistId = '';
  List<DownloadItem> _downloads = [];

  final Map<String, http.Client> _activeClients = {};
  final Map<String, IOSink> _activeSinks = {};

  List<DownloadItem> get downloading =>
      _downloads.where((d) => d.status == DownloadStatus.downloading).toList();

  List<DownloadItem> get completedDownloads =>
      _downloads.where((d) => d.status == DownloadStatus.completed).toList();

  List<DownloadItem> get failedDownloads =>
      _downloads.where((d) => d.status == DownloadStatus.failed).toList();

  bool isDownloaded(String id) =>
      _downloads.any((d) => d.id == id && d.status == DownloadStatus.completed);

  bool isDownloading(String id) =>
      _downloads.any((d) => d.id == id && d.status == DownloadStatus.downloading);

  DownloadItem? itemFor(String id) {
    try {
      return _downloads.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  // ─── Playlist Scoping ──────────────────────────────────────────────────────

  Future<void> setPlaylistId(String id) async {
    if (id.isEmpty || id == _playlistId) return;
    await _cancelAllActive();
    _playlistId = id;
    await _load();
  }

  Future<void> reset() async {
    await _cancelAllActive();
    _playlistId = '';
    _downloads = [];
    notifyListeners();
  }

  Future<void> deletePlaylistData(String playlistId) async {
    if (playlistId.isEmpty) return;

    // Cancel (and persist the cancellation of) any in-flight transfers
    // *before* wiping storage below — otherwise that persist would recreate
    // the prefs key we're about to remove.
    if (playlistId == _playlistId) {
      await _cancelAllActive();
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
      _downloads = raw.map((e) => DownloadItem.fromJson(jsonDecode(e))).toList();
      // A "downloading" entry that survived a full app restart has no live
      // stream behind it anymore — surface it as failed instead of a
      // progress bar that will never move again.
      for (final d in _downloads) {
        if (d.status == DownloadStatus.downloading) {
          d.status = DownloadStatus.failed;
        }
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_playlistId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'downloads_$_playlistId',
      _downloads.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  // ─── Transfers ──────────────────────────────────────────────────────────────

  String _guessExtension(String url, Map<String, dynamic> rawData) {
    final containerExt = rawData['container_extension']?.toString();
    if (containerExt != null && containerExt.isNotEmpty) return containerExt;
    final uri = Uri.tryParse(url);
    final last =
        (uri != null && uri.pathSegments.isNotEmpty) ? uri.pathSegments.last : '';
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

    final ownerPlaylistId = _playlistId;
    final dir = await _ensureDirFor(ownerPlaylistId);
    final ext = _guessExtension(sourceUrl, rawData);
    final path = '${dir.path}/$id.$ext';

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

    final client = http.Client();
    _activeClients[id] = client;

    try {
      final request = http.Request('GET', Uri.parse(sourceUrl));
      request.headers.addAll(headers);
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Server returned ${response.statusCode}');
      }

      item.totalBytes = response.contentLength ?? 0;

      final sink = File(path).openWrite();
      _activeSinks[id] = sink;

      var lastNotify = DateTime.now();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        item.downloadedBytes += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds > 250) {
          lastNotify = now;
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      _activeSinks.remove(id);
      _activeClients.remove(id);

      if (ownerPlaylistId != _playlistId) return; // account switched mid-download

      item.status = DownloadStatus.completed;
      notifyListeners();
      await _persist();
    } catch (_) {
      _activeSinks.remove(id);
      _activeClients.remove(id);
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (ownerPlaylistId == _playlistId) {
        _downloads.removeWhere((d) => d.id == id);
        notifyListeners();
        await _persist();
      }
    } finally {
      client.close();
    }
  }

  Future<void> cancelDownload(String id) async {
    await _cancelDownloadInternal(id);
    _downloads.removeWhere((d) => d.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> _cancelDownloadInternal(String id) async {
    final client = _activeClients.remove(id);
    client?.close();
    final sink = _activeSinks.remove(id);
    try {
      await sink?.close();
    } catch (_) {}
    final item = itemFor(id);
    final path = item?.filePath;
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _cancelAllActive() async {
    if (_activeClients.isEmpty) return;
    for (final id in _activeClients.keys.toList()) {
      await _cancelDownloadInternal(id);
      _downloads.removeWhere((d) => d.id == id);
    }
    await _persist();
  }

  /// Deletes a completed (or failed) download's file and removes it from the
  /// list — the originating download button reverts to its plain "download"
  /// state once this completes, since [isDownloaded]/[isDownloading] both
  /// become false.
  Future<void> deleteDownload(String id) async {
    final item = itemFor(id);
    if (item == null) return;

    if (item.status == DownloadStatus.downloading) {
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
