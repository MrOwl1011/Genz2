import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      positionMilliseconds: json['positionMilliseconds'] ?? (json['positionSeconds'] != null ? (json['positionSeconds'] as int) * 1000 : 0),
      durationMilliseconds: json['durationMilliseconds'] ?? (json['durationSeconds'] != null ? (json['durationSeconds'] as int) * 1000 : 0),
      rawData: json['rawData'],
      lastWatched: DateTime.parse(json['lastWatched']),
    );
  }
}

class UserPrefsProvider extends ChangeNotifier {
  String _favoritesKey = 'favorites_v1';
  String _historyKey = 'history_v1';
  String _currentPlaylistId = '';

  List<FavoriteItem> _favorites = [];
  List<HistoryItem> _history = [];
  String _locale = 'en'; // Default English

  List<FavoriteItem> get favorites => _favorites;
  List<HistoryItem> get history => _history;
  String get locale => _locale;
  String get currentPlaylistId => _currentPlaylistId;

  Future<void> setLocale(String locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', locale);
    notifyListeners();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Locale
    _locale = prefs.getString('app_locale') ?? 'en';
    
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

  Future<void> _loadDataFromCurrentKeys(SharedPreferences prefs) async {
    // Load Favorites
    final favStr = prefs.getStringList(_favoritesKey);
    if (favStr != null) {
      _favorites = favStr.map((e) => FavoriteItem.fromJson(jsonDecode(e))).toList();
    } else {
      _favorites = [];
    }

    // Load History
    final histStr = prefs.getStringList(_historyKey);
    if (histStr != null) {
      _history = histStr.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
      // Sort by last watched descending
      _history.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    } else {
      _history = [];
    }
    
    notifyListeners();
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = _favorites.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_favoritesKey, favList);
    notifyListeners();
  }

  Future<void> _saveHistory() async {
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
    if (isFavorite(id)) {
      _favorites.removeWhere((item) => item.id == id);
    } else {
      _favorites.add(FavoriteItem(
        id: id,
        title: title,
        posterUrl: posterUrl,
        type: type,
        rawData: rawData,
      ));
    }
    _saveFavorites();
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
        _history.removeWhere((item) =>
          item.type == MediaType.series &&
          item.rawData['series_id'] == seriesId
        );
      }
    }
    
    _history.insert(0, HistoryItem(
      id: id,
      title: title,
      posterUrl: posterUrl,
      type: type,
      positionMilliseconds: positionMilliseconds,
      durationMilliseconds: durationMilliseconds,
      rawData: rawData,
      lastWatched: DateTime.now(),
    ));

    // Limit history size to e.g., 50 items
    if (_history.length > 50) {
      _history = _history.sublist(0, 50);
    }

    _saveHistory();
  }

  int getHistoryPosition(String id) {
    try {
      final item = _history.firstWhere((item) => item.id == id);
      // If watched more than 95%, start over
      if (item.durationMilliseconds > 0 && item.positionMilliseconds >= item.durationMilliseconds - 10000) {
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
      // If watched more than 95%, start over
      if (item.durationMilliseconds > 0 && item.positionMilliseconds >= item.durationMilliseconds - 10000) {
        return 0;
      }
      return item.positionMilliseconds;
    } catch (_) {
      return 0;
    }
  }

  void clearHistory() {
    _history.clear();
    _saveHistory();
  }
}
