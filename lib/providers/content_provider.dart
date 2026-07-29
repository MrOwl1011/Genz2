import 'package:flutter/material.dart';
import '../models/xtream_models.dart';
import '../models/search_results_model.dart';
import '../services/xtream_api_service.dart';

class ContentProvider extends ChangeNotifier {
  final XtreamApiService _api = XtreamApiService();

  // ─── Credentials ────────────────────────────────────────────────────────────
  String _serverUrl = '';
  String _username = '';
  String _password = '';

  String get serverUrl => _serverUrl;
  String get username => _username;
  String get password => _password;
  String get baseUrl => XtreamApiService.getBaseUrl(_serverUrl);

  // ─── Live Categories ────────────────────────────────────────────────────────
  List<XtreamCategory> _liveCategories = [];
  bool _isLoadingLive = false;
  String? _liveError;

  List<XtreamCategory> get liveCategories => _liveCategories;
  bool get isLoadingLive => _isLoadingLive;
  String? get liveError => _liveError;

  // ─── VOD Categories ─────────────────────────────────────────────────────────
  List<XtreamCategory> _vodCategories = [];
  bool _isLoadingVod = false;
  String? _vodError;

  List<XtreamCategory> get vodCategories => _vodCategories;
  bool get isLoadingVod => _isLoadingVod;
  String? get vodError => _vodError;

  // ─── Series Categories ──────────────────────────────────────────────────────
  List<XtreamCategory> _seriesCategories = [];
  bool _isLoadingSeries = false;
  String? _seriesError;

  List<XtreamCategory> get seriesCategories => _seriesCategories;
  bool get isLoadingSeries => _isLoadingSeries;
  String? get seriesError => _seriesError;

  // ─── Setup ──────────────────────────────────────────────────────────────────

  void setCredentials(String serverUrl, String username, String password) {
    final changed = _serverUrl != serverUrl ||
        _username != username ||
        _password != password;
    _serverUrl = serverUrl;
    _username = username;
    _password = password;
    if (changed && serverUrl.isNotEmpty) {
      loadAllCategories();
    }
  }

  Future<void> loadAllCategories() async {
    await Future.wait([
      loadLiveCategories(),
      loadVodCategories(),
      loadSeriesCategories(),
    ]);
    await loadNewContent();
  }

  // ─── Live ────────────────────────────────────────────────────────────────────

  Future<void> loadLiveCategories() async {
    if (_serverUrl.isEmpty) return;
    _isLoadingLive = true;
    _liveError = null;
    notifyListeners();
    try {
      _liveCategories = await _api.getLiveCategories(
        serverUrl: _serverUrl,
        username: _username,
        password: _password,
      );
    } catch (e) {
      _liveError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingLive = false;
      notifyListeners();
    }
  }

  Future<List<XtreamLiveStream>> getLiveStreams({String? categoryId}) async {
    return _api.getLiveStreams(
      serverUrl: _serverUrl,
      username: _username,
      password: _password,
      categoryId: categoryId,
    );
  }

  // ─── VOD ─────────────────────────────────────────────────────────────────────

  Future<void> loadVodCategories() async {
    if (_serverUrl.isEmpty) return;
    _isLoadingVod = true;
    _vodError = null;
    notifyListeners();
    try {
      _vodCategories = await _api.getVodCategories(
        serverUrl: _serverUrl,
        username: _username,
        password: _password,
      );
    } catch (e) {
      _vodError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingVod = false;
      notifyListeners();
    }
  }

  Future<List<XtreamVodStream>> getVodStreams({String? categoryId}) async {
    return _api.getVodStreams(
      serverUrl: _serverUrl,
      username: _username,
      password: _password,
      categoryId: categoryId,
    );
  }

  Future<XtreamVodInfo?> getVodInfo(int vodId) async {
    return _api.getVodInfo(
      serverUrl: _serverUrl,
      username: _username,
      password: _password,
      vodId: vodId,
    );
  }

  // ─── Home Screen "New" Content ──────────────────────────────────────────────
  List<XtreamVodStream> _newMovies = [];
  List<XtreamSeries> _newSeries = [];
  bool _isLoadingNewContent = false;

  List<XtreamVodStream> get newMovies => _newMovies;
  List<XtreamSeries> get newSeries => _newSeries;
  bool get isLoadingNewContent => _isLoadingNewContent;

  Future<void> loadNewContent() async {
    if (_serverUrl.isEmpty) return;
    _isLoadingNewContent = true;
    notifyListeners();
    try {
      // Movies: newest across all VOD categories.
      final movies = await getVodStreams();
      movies.sort((a, b) => b.added.compareTo(a.added));
      _newMovies = movies.take(20).toList();

      // Series: newest across all series categories except the first one.
      if (_seriesCategories.isNotEmpty) {
        final excludedCategoryId = _seriesCategories.first.categoryId;
        final series = await getSeriesList();
        final eligible = series
            .where((s) => s.categoryId != excludedCategoryId)
            .toList();
        eligible.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        _newSeries = eligible.take(20).toList();
      }
    } catch (e) {
      // Handle silently
    } finally {
      _isLoadingNewContent = false;
      notifyListeners();
    }
  }

  // ─── Series ───────────────────────────────────────────────────────────────────

  Future<void> loadSeriesCategories() async {
    if (_serverUrl.isEmpty) return;
    _isLoadingSeries = true;
    _seriesError = null;
    notifyListeners();
    try {
      _seriesCategories = await _api.getSeriesCategories(
        serverUrl: _serverUrl,
        username: _username,
        password: _password,
      );
    } catch (e) {
      _seriesError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoadingSeries = false;
      notifyListeners();
    }
  }

  Future<List<XtreamSeries>> getSeriesList({String? categoryId}) async {
    return _api.getSeriesList(
      serverUrl: _serverUrl,
      username: _username,
      password: _password,
      categoryId: categoryId,
    );
  }

  Future<XtreamSeriesInfo?> getSeriesInfo(int seriesId) async {
    return _api.getSeriesInfo(
      serverUrl: _serverUrl,
      username: _username,
      password: _password,
      seriesId: seriesId,
    );
  }

  // ─── Global Search ────────────────────────────────────────────────────────────

  List<XtreamVodStream> _allMovies = [];
  List<XtreamSeries> _allSeries = [];
  List<XtreamLiveStream> _allLiveStreams = [];

  bool _isAllContentLoaded = false;
  bool _isLoadingAllContent = false;

  bool get isLoadingAllContent => _isLoadingAllContent;
  bool get isAllContentLoaded => _isAllContentLoaded;

  Future<void> loadAllContent() async {
    if (_serverUrl.isEmpty || _isAllContentLoaded || _isLoadingAllContent) return;

    _isLoadingAllContent = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        getVodStreams(),
        getSeriesList(),
        getLiveStreams(),
      ]);

      _allMovies = results[0] as List<XtreamVodStream>;
      _allSeries = results[1] as List<XtreamSeries>;
      _allLiveStreams = results[2] as List<XtreamLiveStream>;

      _isAllContentLoaded = true;
    } catch (e) {
      // Handle silently or log
    } finally {
      _isLoadingAllContent = false;
      notifyListeners();
    }
  }

  SearchResults searchAll(String query) {
    if (query.trim().isEmpty) {
      return SearchResults(movies: [], series: [], liveStreams: []);
    }

    final lowerQuery = query.toLowerCase();

    final movies = _allMovies
        .where((m) => m.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();

    final series = _allSeries
        .where((s) => s.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();

    final liveStreams = _allLiveStreams
        .where((l) => l.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();

    return SearchResults(
      movies: movies,
      series: series,
      liveStreams: liveStreams,
    );
  }

  // ─── Reset ───────────────────────────────────────────────────────────────────

  void reset() {
    _serverUrl = '';
    _username = '';
    _password = '';
    _liveCategories = [];
    _vodCategories = [];
    _seriesCategories = [];
    _liveError = null;
    _vodError = null;
    _seriesError = null;
    
    _allMovies = [];
    _allSeries = [];
    _allLiveStreams = [];
    _isAllContentLoaded = false;
    
    notifyListeners();
  }
}
