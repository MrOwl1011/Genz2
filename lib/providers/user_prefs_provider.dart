import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/datetime_utils.dart';
import '../core/hive/hive_boxes.dart';
import '../features/sync/services/sync_manager.dart';
import '../services/backend_api_service.dart';

enum MediaType { movie, series, live }

class FavoriteItem {
  final String id;
  final String title;
  final String posterUrl;
  final MediaType type;
  // Store raw object json to recreate it when clicked from favorites
  final Map<String, dynamic> rawData;

  FavoriteItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.type,
    required this.rawData,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'posterUrl': posterUrl,
    'type': type.name,
    'rawData': rawData,
  };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: json['id'],
      title: json['title'],
      posterUrl: json['posterUrl'],
      type: MediaType.values.firstWhere((e) => e.name == json['type']),
      rawData: json['rawData'],
    );
  }
}

class HistoryItem {
  final String id;
  final String title;
  final String posterUrl;
  final MediaType type;
  final int positionMilliseconds;
  final int durationMilliseconds;
  final Map<String, dynamic> rawData;
  final DateTime lastWatched;

  HistoryItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.type,
    required this.positionMilliseconds,
    required this.durationMilliseconds,
    required this.rawData,
    required this.lastWatched,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'posterUrl': posterUrl,
    'type': type.name,
    'positionMilliseconds': positionMilliseconds,
    'durationMilliseconds': durationMilliseconds,
    'rawData': rawData,
    'lastWatched': lastWatched.toIso8601String(),
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: json['id'],
      title: json['title'],
      posterUrl: json['posterUrl'],
      type: MediaType.values.firstWhere((e) => e.name == json['type']),
      positionMilliseconds:
          json['positionMilliseconds'] ??
          (json['positionSeconds'] != null
              ? (json['positionSeconds'] as int) * 1000
              : 0),
      durationMilliseconds:
          json['durationMilliseconds'] ??
          (json['durationSeconds'] != null
              ? (json['durationSeconds'] as int) * 1000
              : 0),
      rawData: json['rawData'],
      lastWatched: DateTime.parse(json['lastWatched']),
    );
  }
}

class UserPrefsProvider extends ChangeNotifier {
  String _favoritesKey = 'favorites_v1';
  String _historyKey = 'history_v1';
  String _currentPlaylistId = '';

  // ─── Profile scoping (additive — see setProfileScope) ──────────────────────
  // Once a profile is selected (Netflix-style profiles feature), favorites/
  // history switch from the legacy playlistId-scoped SharedPreferences keys
  // above to a Hive-backed store keyed by (accountId, profileId), leaving
  // every existing public method's signature untouched — see
  // migrateLegacyPlaylistDataToProfile for how existing users' data crosses
  // over the first time this activates for their account.
  bool _useProfileScope = false;
  String? _profileAccountId;
  String? _profileId;
  String get _profileHiveKey => '${_profileAccountId}__$_profileId';

  List<FavoriteItem> _favorites = [];
  List<HistoryItem> _history = [];
  String _locale = 'en'; // Default English
  bool _autoPlayNextEpisode = true;
  // Defaults to dark to preserve the app's current look for existing users —
  // System is offered as a picker choice but is never the default, so nobody's
  // view silently flips to light because their OS happens to be in light mode.
  ThemeMode _themeMode = ThemeMode.dark;
  // Device-level (not playlist-scoped) — the gesture tutorial is about the
  // player UI itself, not any one account's data.
  bool _hasSeenPlayerTutorial = false;

  List<FavoriteItem> get favorites => _favorites;
  List<HistoryItem> get history => _history;
  String get locale => _locale;
  String get currentPlaylistId => _currentPlaylistId;
  bool get autoPlayNextEpisode => _autoPlayNextEpisode;
  ThemeMode get themeMode => _themeMode;
  bool get hasSeenPlayerTutorial => _hasSeenPlayerTutorial;

  Future<void> setLocale(String locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', locale);
    notifyListeners();
  }

  Future<void> setAutoPlayNextEpisode(bool value) async {
    _autoPlayNextEpisode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_play_next', value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
    notifyListeners();
  }

  Future<void> markPlayerTutorialSeen() async {
    if (_hasSeenPlayerTutorial) return;
    _hasSeenPlayerTutorial = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_player_tutorial', true);
    notifyListeners();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Locale
    _locale = prefs.getString('app_locale') ?? 'en';

    // Load Auto Play
    _autoPlayNextEpisode = prefs.getBool('auto_play_next') ?? true;

    // Load whether the player's brightness/volume gesture tutorial was
    // already dismissed once (device-level, shown at most once ever).
    _hasSeenPlayerTutorial = prefs.getBool('has_seen_player_tutorial') ?? false;

    // Load Theme Mode
    final savedThemeMode = prefs.getString('theme_mode');
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == savedThemeMode,
      orElse: () => ThemeMode.dark,
    );

    await _loadDataFromCurrentKeys(prefs);
  }

  Future<void> setPlaylistId(String playlistId) async {
    if (playlistId.isEmpty) return;

    _currentPlaylistId = playlistId;
    _favoritesKey = 'favorites_$playlistId';
    _historyKey = 'history_$playlistId';

    final prefs = await SharedPreferences.getInstance();
    await _loadDataFromCurrentKeys(prefs);
  }

  /// Switches favorites/history from account-level (legacy playlistId)
  /// scoping to profile-level scoping — called once a profile is selected
  /// (see ProfileProvider.selectProfile). Every existing public method below
  /// (toggleFavorite, saveHistory, getHistoryPosition, etc.) keeps working
  /// exactly as before; only the underlying storage this switches to.
  ///
  /// If [deviceToken] is available, also pulls this profile's favorites/
  /// history from the backend afterward (best-effort, non-blocking) — see
  /// _pullAndMergeFromBackend for the merge strategy and its trade-offs.
  Future<void> setProfileScope(
    String accountId,
    String profileId, {
    String? deviceToken,
    DateTime? favoritesClearedAt,
    DateTime? historyClearedAt,
  }) async {
    _useProfileScope = true;
    _profileAccountId = accountId;
    _profileId = profileId;
    await _loadProfileScopedData();
    await _applyAdminClearMarkersIfNeeded(
      profileId,
      favoritesClearedAt: favoritesClearedAt,
      historyClearedAt: historyClearedAt,
    );

    if (deviceToken != null) {
      unawaited(_pullAndMergeFromBackend(deviceToken));
    }
  }

  String _favoritesClearedMarkerKey(String profileId) =>
      'favorites_cleared_ack_$profileId';
  String _historyClearedMarkerKey(String profileId) =>
      'history_cleared_ack_$profileId';

  /// The admin panel's "Clear Favorites"/"Clear History" actions delete rows
  /// server-side and stamp profiles.favorites_cleared_at/history_cleared_at
  /// — but the normal sync merge below only ever *adds* items it doesn't
  /// have locally, it never removes ones the device already cached. Without
  /// this, an admin clearing a profile's data server-side had no visible
  /// effect at all: the device just kept showing what it already had.
  ///
  /// Compares each timestamp against a locally stored "last applied" marker
  /// (so the same clear isn't reapplied — and doesn't wipe out favorites/
  /// history the user has added since) and wipes the local list only when
  /// the server's marker is newer than what this device has already acted
  /// on. Runs before the pull-merge so the subsequent pull repopulates from
  /// the (now genuinely current) server state rather than fighting a stale
  /// local cache.
  Future<void> _applyAdminClearMarkersIfNeeded(
    String profileId, {
    DateTime? favoritesClearedAt,
    DateTime? historyClearedAt,
  }) async {
    if (favoritesClearedAt != null) {
      final ackKey = _favoritesClearedMarkerKey(profileId);
      final lastAck = HiveBoxes.metaBox.get(ackKey) as String?;
      final alreadyApplied =
          lastAck != null &&
          !favoritesClearedAt.isAfter(DateTime.parse(lastAck));
      if (!alreadyApplied) {
        _favorites = [];
        await _saveFavorites();
        await HiveBoxes.metaBox.put(
          ackKey,
          favoritesClearedAt.toUtc().toIso8601String(),
        );
      }
    }
    if (historyClearedAt != null) {
      final ackKey = _historyClearedMarkerKey(profileId);
      final lastAck = HiveBoxes.metaBox.get(ackKey) as String?;
      final alreadyApplied =
          lastAck != null && !historyClearedAt.isAfter(DateTime.parse(lastAck));
      if (!alreadyApplied) {
        _history = [];
        await _saveHistory();
        await HiveBoxes.metaBox.put(
          ackKey,
          historyClearedAt.toUtc().toIso8601String(),
        );
      }
    }
  }

  /// Merges this profile's server-side favorites/history into the local
  /// cache — the "other devices' changes show up here" half of sync (the
  /// enqueue* calls in toggleFavorite/saveHistory below are the other half).
  ///
  /// Favorites merge as a union, remote winning on overlap: FavoriteItem has
  /// no timestamp of its own to compare (it's just "is this favorited or
  /// not"), so a true last-write-wins isn't possible without adding one —
  /// deliberately not changing that existing model for this. Practical
  /// effect: a favorite added on another device always shows up here; a
  /// favorite *removed* on another device while this device was offline
  /// won't disappear from here until this device also removes it. Accepted
  /// trade-off for this phase — never silently loses a locally-added
  /// favorite by having it vanish out from under the user.
  ///
  /// History merges with genuine last-write-wins, since HistoryItem already
  /// has lastWatched to compare against the server's updated_at.
  Future<void> _pullAndMergeFromBackend(String token) async {
    final profileId = _profileId;
    if (profileId == null) return;

    try {
      final api = BackendApiService();
      final remoteFavorites = await api.getFavorites(token, profileId);
      final remoteHistory = await api.getHistory(token, profileId);

      for (final r in remoteFavorites) {
        final id = (r['stream_id'] ?? '').toString();
        if (id.isEmpty) continue;
        _favorites.removeWhere((f) => f.id == id);
        _favorites.add(
          FavoriteItem(
            id: id,
            title: (r['title'] as String?) ?? '',
            posterUrl: (r['poster_url'] as String?) ?? '',
            type: MediaType.values.firstWhere(
              (t) => t.name == r['stream_type'],
              orElse: () => MediaType.movie,
            ),
            rawData: r['raw_data'] is Map
                ? Map<String, dynamic>.from(r['raw_data'] as Map)
                : {},
          ),
        );
      }

      for (final r in remoteHistory) {
        final id = (r['stream_id'] ?? '').toString();
        if (id.isEmpty || r['updated_at'] == null) continue;
        final remoteUpdatedAt = parseBackendUtc(r['updated_at'] as String);
        final existingIndex = _history.indexWhere((h) => h.id == id);
        final isNewer =
            existingIndex == -1 ||
            remoteUpdatedAt.isAfter(_history[existingIndex].lastWatched);
        if (!isNewer) continue;

        final item = HistoryItem(
          id: id,
          title: (r['title'] as String?) ?? '',
          posterUrl: (r['poster_url'] as String?) ?? '',
          type: MediaType.values.firstWhere(
            (t) => t.name == r['stream_type'],
            orElse: () => MediaType.movie,
          ),
          positionMilliseconds:
              (((r['position_seconds'] as num?) ?? 0).toInt()) * 1000,
          durationMilliseconds:
              (((r['duration_seconds'] as num?) ?? 0).toInt()) * 1000,
          rawData: r['raw_data'] is Map
              ? Map<String, dynamic>.from(r['raw_data'] as Map)
              : {},
          lastWatched: remoteUpdatedAt,
        );
        if (existingIndex == -1) {
          _history.add(item);
        } else {
          _history[existingIndex] = item;
        }

        // Same series-level dedup saveHistory() applies locally — a pull
        // merges purely by per-episode id, so without this it silently
        // reintroduces older episodes of the same series that a previous
        // saveHistory() call had already superseded (e.g. rows from before
        // the backend itself started cleaning these up on save).
        if (item.type == MediaType.series) {
          final seriesId = item.rawData['series_id'];
          if (seriesId != null) {
            _history.removeWhere(
              (h) =>
                  h.id != item.id &&
                  h.type == MediaType.series &&
                  h.rawData['series_id'] == seriesId &&
                  h.lastWatched.isBefore(item.lastWatched),
            );
          }
        }
      }
      _history.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
      if (_history.length > 50) _history = _history.sublist(0, 50);

      await _saveFavorites();
      await _saveHistory();
    } on BackendApiException {
      // Best-effort — local cache (already loaded before this ran) stays as
      // the source of truth if the pull fails; enqueued local changes still
      // get pushed regardless via SyncManager's own retry.
    }
  }

  /// Favorites/history are stored in Hive as a JSON-encoded **string**, not
  /// a raw Hive Map — see HiveBoxes.favoritesBox's doc comment for why
  /// (silent write failures observed with nested Xtream rawData stored as a
  /// native Hive Map; encoding to a string first sidesteps that entirely).
  List<FavoriteItem> _decodeFavoritesJson(dynamic raw) {
    if (raw is! String || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map(
            (e) => FavoriteItem.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<HistoryItem> _decodeHistoryJson(dynamic raw) {
    if (raw is! String || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => HistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadProfileScopedData() async {
    _favorites = _decodeFavoritesJson(
      HiveBoxes.favoritesBox.get(_profileHiveKey),
    );
    _history = _decodeHistoryJson(HiveBoxes.historyBox.get(_profileHiveKey))
      ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));

    notifyListeners();
  }

  /// One-time migration: copies whatever favorites/history exist under the
  /// OLD playlistId-scoped SharedPreferences keys into the NEW profile-scoped
  /// Hive storage for (accountId, profileId), then switches this provider
  /// into profile-scoped mode. Called by AuthProvider the first time an
  /// account has no profiles yet — covers both a brand new install and an
  /// existing pre-profiles-feature user upgrading.
  ///
  /// The old SharedPreferences data is deliberately left in place afterward
  /// — untouched, not read again, not deleted — as a cheap, harmless
  /// rollback safety net. "No data loss allowed."
  Future<void> migrateLegacyPlaylistDataToProfile(
    String oldPlaylistId,
    String accountId,
    String profileId,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final favStr = prefs.getStringList('favorites_$oldPlaylistId');
    final legacyFavorites = favStr != null
        ? favStr.map((e) => FavoriteItem.fromJson(jsonDecode(e))).toList()
        : <FavoriteItem>[];

    final histStr = prefs.getStringList('history_$oldPlaylistId');
    final legacyHistory = histStr != null
        ? histStr.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList()
        : <HistoryItem>[];
    legacyHistory.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));

    _useProfileScope = true;
    _profileAccountId = accountId;
    _profileId = profileId;
    _favorites = legacyFavorites;
    _history = legacyHistory;

    await HiveBoxes.favoritesBox.put(
      _profileHiveKey,
      jsonEncode(_favorites.map((e) => e.toJson()).toList()),
    );
    await HiveBoxes.historyBox.put(
      _profileHiveKey,
      jsonEncode(_history.map((e) => e.toJson()).toList()),
    );

    // Migrated data is only local until it's actually pushed — without this,
    // it would sit on this one device forever, never reaching other devices
    // or surviving a reinstall. Uses "now" as each item's sync timestamp
    // (favorites have no timestamp of their own; history already has
    // lastWatched, which is more meaningful and used instead).
    final now = DateTime.now().toUtc();
    for (final f in _favorites) {
      unawaited(
        SyncManager.instance.enqueueFavoriteAdd(
          accountId: accountId,
          profileId: profileId,
          streamId: f.id,
          streamType: f.type.name,
          title: f.title,
          posterUrl: f.posterUrl,
          rawData: f.rawData,
          updatedAt: now,
        ),
      );
    }
    for (final h in _history) {
      unawaited(
        SyncManager.instance.enqueueHistorySave(
          accountId: accountId,
          profileId: profileId,
          streamId: h.id,
          streamType: h.type.name,
          episodeId: h.rawData['episode_id']?.toString(),
          seriesId: h.rawData['series_id']?.toString(),
          title: h.title,
          posterUrl: h.posterUrl,
          positionSeconds: (h.positionMilliseconds / 1000).round(),
          durationSeconds: (h.durationMilliseconds / 1000).round(),
          rawData: h.rawData,
          updatedAt: h.lastWatched.toUtc(),
        ),
      );
    }

    notifyListeners();
  }

  Future<void> deletePlaylistData(String playlistId) async {
    if (playlistId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('favorites_$playlistId');
    await prefs.remove('history_$playlistId');

    // If the deleted data was the currently active one, clear local state
    if (_currentPlaylistId == playlistId) {
      _favorites.clear();
      _history.clear();
      _currentPlaylistId = '';
      notifyListeners();
    }
  }

  /// Number of history entries for a given playlist, without disturbing
  /// whichever playlist is currently active.
  Future<int> getHistoryCountForPlaylist(String playlistId) async {
    if (playlistId.isEmpty) return 0;
    if (playlistId == _currentPlaylistId) return _history.length;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('history_$playlistId')?.length ?? 0;
  }

  /// Read-only peek at another (or the active) playlist's history without
  /// switching the active session.
  Future<List<HistoryItem>> peekHistoryForPlaylist(String playlistId) async {
    if (playlistId.isEmpty) return [];
    if (playlistId == _currentPlaylistId) return _history;
    final prefs = await SharedPreferences.getInstance();
    final histStr = prefs.getStringList('history_$playlistId');
    if (histStr == null) return [];
    final items = histStr
        .map((e) => HistoryItem.fromJson(jsonDecode(e)))
        .toList();
    items.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return items;
  }

  /// Carries favorites/history from an old playlist id to a new one — used
  /// when editing a playlist's server URL or username changes its computed id,
  /// so its local data isn't silently orphaned.
  Future<void> migratePlaylistData(String oldId, String newId) async {
    if (oldId.isEmpty || newId.isEmpty || oldId == newId) return;
    final prefs = await SharedPreferences.getInstance();

    final oldFavorites = prefs.getStringList('favorites_$oldId');
    if (oldFavorites != null) {
      await prefs.setStringList('favorites_$newId', oldFavorites);
      await prefs.remove('favorites_$oldId');
    }

    final oldHistory = prefs.getStringList('history_$oldId');
    if (oldHistory != null) {
      await prefs.setStringList('history_$newId', oldHistory);
      await prefs.remove('history_$oldId');
    }

    // If the new id is (or becomes) the active one, refresh in-memory state.
    if (_currentPlaylistId == newId) {
      await _loadDataFromCurrentKeys(prefs);
    }
  }

  Future<void> _loadDataFromCurrentKeys(SharedPreferences prefs) async {
    // Load Favorites
    final favStr = prefs.getStringList(_favoritesKey);
    if (favStr != null) {
      _favorites = favStr
          .map((e) => FavoriteItem.fromJson(jsonDecode(e)))
          .toList();
    } else {
      _favorites = [];
    }

    // Load History
    final histStr = prefs.getStringList(_historyKey);
    if (histStr != null) {
      _history = histStr
          .map((e) => HistoryItem.fromJson(jsonDecode(e)))
          .toList();
      // Sort by last watched descending
      _history.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    } else {
      _history = [];
    }

    notifyListeners();
  }

  Future<void> _saveFavorites() async {
    if (_useProfileScope) {
      try {
        await HiveBoxes.favoritesBox.put(
          _profileHiveKey,
          jsonEncode(_favorites.map((e) => e.toJson()).toList()),
        );
      } catch (e) {
        // Was previously a fire-and-forget, uncaught async failure here —
        // logging it now rather than letting it disappear silently, so a
        // future report of "it didn't save" has a trail to follow.
        debugPrint('[UserPrefsProvider] failed to persist favorites: $e');
      }
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final favList = _favorites.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_favoritesKey, favList);
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    if (_useProfileScope) {
      try {
        await HiveBoxes.historyBox.put(
          _profileHiveKey,
          jsonEncode(_history.map((e) => e.toJson()).toList()),
        );
      } catch (e) {
        debugPrint('[UserPrefsProvider] failed to persist history: $e');
      }
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final histList = _history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_historyKey, histList);
    notifyListeners();
  }

  // ─── Favorites ───────────────────────────────────────────────────────────────

  bool isFavorite(String id) {
    return _favorites.any((item) => item.id == id);
  }

  void toggleFavorite({
    required String id,
    required String title,
    required String posterUrl,
    required MediaType type,
    required Map<String, dynamic> rawData,
  }) {
    final wasFavorite = isFavorite(id);
    if (wasFavorite) {
      _favorites.removeWhere((item) => item.id == id);
    } else {
      _favorites.add(
        FavoriteItem(
          id: id,
          title: title,
          posterUrl: posterUrl,
          type: type,
          rawData: rawData,
        ),
      );
    }
    _saveFavorites();

    if (_useProfileScope && _profileAccountId != null && _profileId != null) {
      final now = DateTime.now().toUtc();
      if (wasFavorite) {
        unawaited(
          SyncManager.instance.enqueueFavoriteRemove(
            accountId: _profileAccountId!,
            profileId: _profileId!,
            streamId: id,
            streamType: type.name,
            updatedAt: now,
          ),
        );
      } else {
        unawaited(
          SyncManager.instance.enqueueFavoriteAdd(
            accountId: _profileAccountId!,
            profileId: _profileId!,
            streamId: id,
            streamType: type.name,
            title: title,
            posterUrl: posterUrl,
            rawData: rawData,
            updatedAt: now,
          ),
        );
      }
    }
  }

  // ─── History ─────────────────────────────────────────────────────────────────

  void saveHistory({
    required String id,
    required String title,
    required String posterUrl,
    required MediaType type,
    required int positionMilliseconds,
    required int durationMilliseconds,
    required Map<String, dynamic> rawData,
  }) {
    // Remove if already exists to move it to the top
    _history.removeWhere((item) => item.id == id);

    // For series episodes, remove any previous episode from the same series
    // so only the latest watched episode is kept per series
    if (type == MediaType.series) {
      final seriesId = rawData['series_id'];
      if (seriesId != null) {
        _history.removeWhere(
          (item) =>
              item.type == MediaType.series &&
              item.rawData['series_id'] == seriesId,
        );
      }
    }

    _history.insert(
      0,
      HistoryItem(
        id: id,
        title: title,
        posterUrl: posterUrl,
        type: type,
        positionMilliseconds: positionMilliseconds,
        durationMilliseconds: durationMilliseconds,
        rawData: rawData,
        lastWatched: DateTime.now(),
      ),
    );

    // Limit history size to e.g., 50 items
    if (_history.length > 50) {
      _history = _history.sublist(0, 50);
    }

    _saveHistory();

    if (_useProfileScope && _profileAccountId != null && _profileId != null) {
      unawaited(
        SyncManager.instance.enqueueHistorySave(
          accountId: _profileAccountId!,
          profileId: _profileId!,
          streamId: id,
          streamType: type.name,
          episodeId: rawData['episode_id']?.toString(),
          seriesId: rawData['series_id']?.toString(),
          title: title,
          posterUrl: posterUrl,
          positionSeconds: (positionMilliseconds / 1000).round(),
          durationSeconds: (durationMilliseconds / 1000).round(),
          rawData: rawData,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  int getHistoryPosition(String id) {
    try {
      final item = _history.firstWhere((item) => item.id == id);
      // If watched more than 95%, start over
      if (item.durationMilliseconds > 0 &&
          item.positionMilliseconds >= item.durationMilliseconds - 10000) {
        return 0;
      }
      return (item.positionMilliseconds / 1000).floor();
    } catch (_) {
      return 0;
    }
  }

  int getHistoryPositionMilliseconds(String id) {
    try {
      final item = _history.firstWhere((item) => item.id == id);
      return item.positionMilliseconds;
    } catch (_) {
      return 0;
    }
  }

  void clearHistory() {
    _history.clear();
    _saveHistory();
  }

  void clearHistoryPosition(String id) {
    _history.removeWhere((item) => item.id == id);
    _saveHistory();
  }
}
