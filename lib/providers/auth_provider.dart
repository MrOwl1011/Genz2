import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/account_id.dart';
import '../features/profiles/presentation/providers/profile_provider.dart';
import '../features/sync/services/sync_manager.dart';
import '../models/playlist_model.dart';
import '../services/backend_api_service.dart';
import '../services/demo_data_service.dart';
import '../services/device_id_service.dart';
import '../services/xtream_api_service.dart';
import 'downloads_provider.dart';
import 'user_prefs_provider.dart';

class AuthProvider extends ChangeNotifier {
  final XtreamApiService _apiService = XtreamApiService();
  final UserPrefsProvider userPrefs;
  final DownloadsProvider downloads;
  final ProfileProvider profileProvider;

  bool _isLoading = false;
  bool _isInitializing = true; // Added for initial app startup
  String? _errorMessage;
  XtreamUser? _user;
  bool _isAuthenticated = false;
  bool _hasSavedPlaylists = false;

  // Stored inputs to autofill or show on dashboard
  String _playlistName = '';
  String _serverUrl = '';
  String _username = '';
  String _password = '';

  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  XtreamUser? get user => _user;
  bool get isAuthenticated => _isAuthenticated;
  bool get hasSavedPlaylists => _hasSavedPlaylists;

  String get playlistName => _playlistName;
  String get serverUrl => _serverUrl;
  String get username => _username;
  String get password => _password;
  String get playlistId =>
      base64Encode(utf8.encode('${_serverUrl}_$_username'));

  /// SHA256(normalize(server_url) + normalize(username)) — the identity used
  /// by the profile/sync backend. Deliberately separate from [playlistId]
  /// above (different formula, different purpose) — see core/account_id.dart.
  String get accountId => computeAccountId(_serverUrl, _username);

  String? _deviceToken;
  /// Bearer token for the profile/sync backend, null whenever it couldn't be
  /// reached (offline, not yet deployed, etc.) — every consumer of this must
  /// treat null as "operate in local-only/cached mode", never as an error.
  String? get deviceToken => _deviceToken;

  /// True when the currently active session is one of the published demo
  /// accounts (App Store / Play Store review) — see [DemoDataService].
  bool get isDemoMode => DemoDataService.isDemoLogin(_serverUrl, _username, _password);

  AuthProvider(this.userPrefs, this.downloads, this.profileProvider) {
    checkAutoLogin();
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
    }
  }

  String get _deviceDisplayName {
    if (kIsWeb) return 'Web Browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iPhone/iPad';
      case TargetPlatform.android:
        return 'Android Device';
      case TargetPlatform.macOS:
        return 'Mac';
      case TargetPlatform.windows:
        return 'Windows PC';
      case TargetPlatform.linux:
        return 'Linux PC';
      default:
        return 'Device';
    }
  }

  /// Registers this device with the profile/sync backend and loads the
  /// account's profile list — called after every successful Xtream login
  /// (explicit or auto-login), never blocking that login's own success:
  /// a failure here (backend down, not deployed yet, offline) is caught and
  /// left non-fatal, matching this feature's offline-first requirement — the
  /// existing Xtream-only login flow must keep working regardless.
  ///
  /// Skipped entirely for demo-mode logins (App Store/Play Store review
  /// accounts) — those are a fabricated, network-free session by design (see
  /// [DemoDataService]) and reviewers should see exactly the same app they
  /// always have, with no new profile-picker step in the way.
  Future<void> _connectBackendAndProfiles() async {
    if (isDemoMode) return;

    try {
      final result = await BackendApiService().login(
        serverUrl: _serverUrl,
        username: _username,
        password: _password,
        deviceId: DeviceIdService.getOrCreate(),
        deviceName: _deviceDisplayName,
        platform: _platformName,
      );
      _deviceToken = result.deviceToken;
    } on BackendApiException catch (e) {
      _deviceToken = null;
      debugPrint('[AuthProvider] backend connect failed (non-fatal): $e');
    }

    SyncManager.instance.updateSession(accountId: accountId, deviceToken: _deviceToken);
    await profileProvider.loadForAccount(accountId, _deviceToken);

    if (profileProvider.profiles.isEmpty) {
      // First time ever for this account — brand new user, or an existing
      // pre-profiles-feature user upgrading. Create a default profile
      // (works fully offline — see ProfileRepository) and, if this device
      // has legacy playlistId-scoped local favorites/history, migrate it in
      // rather than losing it. Deliberately does NOT auto-select the new
      // profile here — the very first time, the "Who's Watching?" picker
      // still shows it and the user taps it themselves, matching normal
      // Netflix-style behavior.
      await profileProvider.createProfile(name: 'Profile 1', avatar: 'purple');
      if (profileProvider.profiles.isNotEmpty) {
        await userPrefs.migrateLegacyPlaylistDataToProfile(
          playlistId,
          accountId,
          profileProvider.profiles.first.profileId,
        );
      }
    } else {
      // Every subsequent login/app-launch: resume whichever profile was
      // active last time, so the picker only appears on first-ever use or
      // when the user explicitly switches via More — not on every single
      // app restart. Without this, ProfileProvider.activeProfile (a plain
      // in-memory field) reset on every fresh process, silently landing back
      // on unscoped legacy storage until the user manually re-picked —
      // easy to mistake for favorites/history having disappeared, when they
      // were actually sitting untouched in both local storage and the
      // backend the whole time.
      profileProvider.tryRestoreLastProfile();
    }
  }

  /// Authenticates against the real Xtream server, unless [serverUrl]/
  /// [username]/[password] match a published demo account — in which case
  /// no network call is made at all and a fabricated demo user is returned
  /// instead. See [DemoDataService].
  Future<XtreamUser> _authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    if (DemoDataService.isDemoLogin(serverUrl, username, password)) {
      return DemoDataService.buildDemoUser(username.trim());
    }
    return _apiService.authenticate(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }

  /// Get the list of all saved playlists
  Future<List<Map<String, String>>> getSavedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final playlistsJson = prefs.getString('saved_playlists');
    if (playlistsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(playlistsJson);
        return decoded.map((e) => Map<String, String>.from(e)).toList();
      } catch (e) {
        return [];
      }
    }

    // Migrate old single credential format if exists
    final savedName = prefs.getString('playlist_name');
    final savedUrl = prefs.getString('server_url');
    final savedUser = prefs.getString('username');
    final savedPass = prefs.getString('password');

    if (savedUrl != null && savedUser != null && savedPass != null) {
      final oldPlaylist = {
        'name': savedName ?? 'My Playlist',
        'url': savedUrl,
        'username': savedUser,
        'password': savedPass,
      };
      await prefs.setString('saved_playlists', jsonEncode([oldPlaylist]));

      // Clear old keys
      await prefs.remove('playlist_name');
      await prefs.remove('server_url');
      await prefs.remove('username');
      await prefs.remove('password');

      return [oldPlaylist];
    }

    return [];
  }

  /// Get saved playlists as typed models (with lastLogin/createdAt parsed).
  Future<List<Playlist>> getSavedPlaylistModels() async {
    final raw = await getSavedPlaylists();
    return raw.map((e) => Playlist.fromMap(e)).toList();
  }

  /// Set the active playlist and save it as the last used
  Future<void> _setActivePlaylist(
    String name,
    String url,
    String username,
    String password,
  ) async {
    _playlistName = name;
    _serverUrl = url;
    _username = username;
    _password = password;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_url', url);
    await prefs.setString('active_username', username);

    // Switch the independent data context
    await userPrefs.setPlaylistId(playlistId);
    await downloads.setPlaylistId(playlistId);
  }

  /// Save a playlist to the stored list
  Future<void> _savePlaylistToList(
    String name,
    String url,
    String username,
    String password, {
    String? oldUrl,
    String? oldUsername,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final playlists = await getSavedPlaylists();

    // Find the existing entry (by old identity if editing, else current identity)
    // so we can preserve its original createdAt timestamp.
    Map<String, String>? existing;
    try {
      existing = playlists.firstWhere(
        (p) => oldUrl != null && oldUsername != null
            ? (p['url'] == oldUrl && p['username'] == oldUsername)
            : (p['url'] == url && p['username'] == username),
      );
    } catch (_) {
      existing = null;
    }

    // If editing an existing playlist, remove the old one
    if (oldUrl != null && oldUsername != null) {
      playlists.removeWhere(
        (p) => p['url'] == oldUrl && p['username'] == oldUsername,
      );
    }

    // Remove if it already exists to avoid duplicates
    playlists.removeWhere((p) => p['url'] == url && p['username'] == username);

    final now = DateTime.now().toIso8601String();

    // Add the new/updated one
    playlists.add({
      'name': name,
      'url': url,
      'username': username,
      'password': password,
      'lastLogin': now,
      'createdAt': existing?['createdAt'] ?? now,
    });

    await prefs.setString('saved_playlists', jsonEncode(playlists));

    // If editing changed the playlist's identity (url/username), its favorites/
    // history live under the old computed id — carry them forward so nothing
    // gets silently orphaned.
    if (oldUrl != null &&
        oldUsername != null &&
        (oldUrl != url || oldUsername != username)) {
      final oldId = base64Encode(utf8.encode('${oldUrl}_$oldUsername'));
      final newId = base64Encode(utf8.encode('${url}_$username'));
      if (oldId != newId) {
        await userPrefs.migratePlaylistData(oldId, newId);
        await downloads.migratePlaylistData(oldId, newId);
      }
    }
  }

  /// Update the name of a saved playlist without logging in
  Future<void> updatePlaylistName(
    String url,
    String username,
    String newName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final playlists = await getSavedPlaylists();

    for (var i = 0; i < playlists.length; i++) {
      if (playlists[i]['url'] == url && playlists[i]['username'] == username) {
        playlists[i]['name'] = newName;
        break;
      }
    }

    await prefs.setString('saved_playlists', jsonEncode(playlists));

    // Update active state if we are modifying the currently active one
    if (_serverUrl == url && _username == username) {
      _playlistName = newName;
    }
    notifyListeners();
  }

  /// Remove a playlist from the stored list
  Future<void> deletePlaylist(String url, String username) async {
    final prefs = await SharedPreferences.getInstance();
    final playlists = await getSavedPlaylists();

    playlists.removeWhere((p) => p['url'] == url && p['username'] == username);
    await prefs.setString('saved_playlists', jsonEncode(playlists));

    // Clean up local data (history, favorites, downloads) for this playlist
    final targetPlaylistId = base64Encode(utf8.encode('${url}_$username'));
    await userPrefs.deletePlaylistData(targetPlaylistId);
    await downloads.deletePlaylistData(targetPlaylistId);

    if (playlists.isEmpty) {
      _hasSavedPlaylists = false;
    }
    notifyListeners();
  }

  /// Check if credentials exist and auto-login
  Future<void> checkAutoLogin() async {
    final playlists = await getSavedPlaylists();

    if (playlists.isNotEmpty) {
      _hasSavedPlaylists = true;
      final prefs = await SharedPreferences.getInstance();
      final activeUrl = prefs.getString('active_url');
      final activeUser = prefs.getString('active_username');

      // Find the last used playlist, or just use the first one if not found
      Map<String, String>? targetPlaylist;
      if (activeUrl != null && activeUser != null) {
        try {
          targetPlaylist = playlists.firstWhere(
            (p) => p['url'] == activeUrl && p['username'] == activeUser,
          );
        } catch (e) {
          targetPlaylist = playlists.first;
        }
      } else {
        _isInitializing = false;
        notifyListeners();
        return;
      }

      await _setActivePlaylist(
        targetPlaylist['name'] ?? 'My Playlist',
        targetPlaylist['url']!,
        targetPlaylist['username']!,
        targetPlaylist['password']!,
      );
      notifyListeners();

      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      try {
        _user = await _authenticate(
          serverUrl: _serverUrl,
          username: _username,
          password: _password,
        );
        _isAuthenticated = true;
        // Stamp last-login on every successful auto-login too, not just
        // explicit logins, so "Last Login Date" reflects real usage.
        await _savePlaylistToList(
          _playlistName,
          _serverUrl,
          _username,
          _password,
        );
        await _connectBackendAndProfiles();
      } catch (e) {
        _isAuthenticated = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      } finally {
        _isLoading = false;
        _isInitializing = false;
        notifyListeners();
      }
    } else {
      _hasSavedPlaylists = false;
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Attempt authentication and save credentials on success
  Future<bool> login(
    String name,
    String url,
    String user,
    String pass, {
    String? oldUrl,
    String? oldUser,
  }) async {
    if (url.trim().isEmpty || user.trim().isEmpty || pass.trim().isEmpty) {
      _errorMessage = 'All fields except name are required';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final authenticatedUser = await _authenticate(
        serverUrl: url,
        username: user,
        password: pass,
      );

      _user = authenticatedUser;
      _isAuthenticated = true;
      final finalName = name.trim().isEmpty ? 'My Playlist' : name.trim();

      await _setActivePlaylist(finalName, url.trim(), user.trim(), pass.trim());
      await _savePlaylistToList(
        finalName,
        url.trim(),
        user.trim(),
        pass.trim(),
        oldUrl: oldUrl,
        oldUsername: oldUser,
      );
      await _connectBackendAndProfiles();

      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isAuthenticated = false;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Log out the current playlist. If true is passed, also delete it from saved list.
  Future<void> logout({bool deleteFromList = false}) async {
    _isLoading = true;
    notifyListeners();

    if (deleteFromList) {
      await deletePlaylist(_serverUrl, _username);
    }

    // Clear active playlist status
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_url');
    await prefs.remove('active_username');

    _user = null;
    _isAuthenticated = false;
    _deviceToken = null;
    _isLoading = false;
    profileProvider.reset();
    SyncManager.instance.updateSession(accountId: null, deviceToken: null);
    notifyListeners();
  }

  /// Helper to clear the login error message
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}
