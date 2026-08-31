import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/uuid.dart';
import '../features/profiles/presentation/providers/profile_provider.dart';
import '../features/sync/services/sync_manager.dart';
import '../models/playlist_model.dart';
import '../services/backend_api_service.dart';
import '../services/device_id_service.dart';
import '../services/device_info_service.dart';
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

  /// Local partition key that every cache keyed by "accountId" outside this
  /// file (ProfileProvider, UserPrefsProvider's favorites/history, Hive
  /// boxes) actually stores its data under. Generated on-device, once per
  /// playlist, the first time it's needed, and cached in SharedPreferences
  /// forever after — so it is available instantly and offline, exactly like
  /// the old SHA256(server_url+username) it replaces.
  ///
  /// It is deliberately NOT the backend's account_id. Nothing in this app
  /// ever sends accountId to the backend — every authenticated call
  /// identifies the account purely from the bearer device token (see
  /// BackendApiService/backend's require_device_token()) — so there is no
  /// need for this local key to match server state, and generating it
  /// locally means local features (the "Who's Watching?" picker above all)
  /// never depend on the backend responding at all, on the very first launch
  /// included.
  ///
  /// This used to be SHA256(server_url + username) instead of random bytes.
  /// That made the backend's own identity automatically credential-derived
  /// too (the same Xtream login always produced the same id, on any
  /// device) — which is what turned an App Store review into a Guideline
  /// 5.6 rejection: a server that authenticates against a user's streaming
  /// service and derives an identity from it reads as operating that
  /// service, not as a neutral player. The backend now mints its own opaque
  /// account_id (see backend/lib/account_id.php's
  /// generate_anonymous_account_id()) with no relation to this value or to
  /// Xtream credentials at all. Multi-device sync still exists; it just
  /// isn't automatic anymore — devices join the same backend account
  /// explicitly, with a pairing code (see createSyncPairingCode/
  /// joinSyncAccount below).
  String? _accountId;
  String? get accountId => _accountId;

  Future<String> _loadOrCreateLocalAccountId() async {
    final key = 'local_account_id_$playlistId';
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(key);
      if (existing != null && existing.isNotEmpty) return existing;
      final generated = generateUuidV4();
      await prefs.setString(key, generated);
      return generated;
    } catch (_) {
      // Storage itself is unavailable — fall back to a value that's at
      // least stable for the lifetime of this provider instance rather than
      // blocking the picker on a retry loop.
      return generateUuidV4();
    }
  }

  String? _deviceToken;

  /// Bearer token for the profile/sync backend, null whenever it couldn't be
  /// reached (offline, not yet deployed, etc.) — every consumer of this must
  /// treat null as "operate in local-only/cached mode", never as an error.
  String? get deviceToken => _deviceToken;

  /// Why the last backend connection attempt failed, or null if it worked.
  ///
  /// Backend failures are deliberately non-fatal (the app runs fine on local
  /// data), but that meant the *reason* only ever went to debugPrint — which
  /// is invisible in a release build on a real TV, where you cannot attach a
  /// debugger. So a device that silently would not sync gave the user, and
  /// anyone debugging it, absolutely nothing to go on. Surfaced read-only in
  /// the More screen's diagnostics row.
  String? _backendError;
  String? get backendError => _backendError;

  /// True once a backend login/token-reuse has actually succeeded.
  bool get isBackendConnected => _deviceToken != null;

  // ─── Device token cache ────────────────────────────────────────────────
  //
  // The backend mints a token good for DEVICE_TOKEN_TTL_DAYS (90 days), but
  // this used to be an in-memory-only field — so every single app launch
  // burned a full login.php round trip re-fetching a token it had already
  // been given. That's not just wasteful, it actively breaks things:
  // login.php is rate limited to LOGIN_RATE_LIMIT_MAX (10) calls per hour
  // *per IP*, and that bucket is shared by every device behind the same
  // router. A household testing a phone, an Android TV box and a simulator
  // — each relaunch costing one call — exhausts the hour's quota quickly,
  // after which further logins come back 429 RATE_LIMITED. That surfaces as
  // a plain non-fatal BackendApiException, so the affected device just
  // silently drops to local-only mode with no visible reason: it looks
  // exactly like "this device can't reach the backend" even though nothing
  // about that device is wrong. Caching the token means a normal relaunch
  // makes zero login calls.
  //
  // Keys are scoped by [playlistId] (not global) — switching between two
  // saved Xtream playlists on the same device gets its own independent
  // device token (and, via _loadOrCreateLocalAccountId above, its own local
  // account partition) rather than sharing one across playlists.
  String _tokenKey(String suffix) => 'backend_${suffix}_$playlistId';

  /// Renew this far ahead of real expiry so a token never lapses mid-session.
  static const Duration _tokenRenewMargin = Duration(days: 1);

  Future<String?> _readCachedDeviceToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey('device_token'));
      final expiryRaw = prefs.getString(_tokenKey('device_token_expires_at'));
      if (token == null || token.isEmpty || expiryRaw == null) return null;
      final expiry = DateTime.tryParse(expiryRaw);
      if (expiry == null) return null;
      final renewAt = expiry.toUtc().subtract(_tokenRenewMargin);
      if (!DateTime.now().toUtc().isBefore(renewAt)) return null;
      return token;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheDeviceToken(String token, DateTime expiresAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey('device_token'), token);
      await prefs.setString(
        _tokenKey('device_token_expires_at'),
        expiresAt.toUtc().toIso8601String(),
      );
    } catch (_) {
      // Cache-only failure: the in-memory token still works for this
      // session, it just won't survive a restart.
    }
  }

  Future<void> _clearCachedDeviceToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey('device_token'));
      await prefs.remove(_tokenKey('device_token_expires_at'));
    } catch (_) {}
  }

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

  /// Registers this device with the profile/sync backend and loads the
  /// account's profile list — called after every successful Xtream login
  /// (explicit or auto-login). Deliberately fire-and-forget from its call
  /// sites (see [login]/[checkAutoLogin]) rather than awaited: this method
  /// makes up to three sequential backend calls (device login, profile
  /// list, profile create), each with its own 15s timeout, so a slow or
  /// cold backend (shared hosting spinning up a PHP process, a flaky
  /// connection) could previously stack up to ~45s of blocking before the
  /// "Who's Watching?" picker could show anything — which read as a hang,
  /// and only "fixed itself" on app restart because the profile created
  /// during that first attempt was already saved locally (writes are
  /// local-first, see ProfileRepositoryImpl.createProfile) and loaded
  /// straight from cache on the next launch. Not awaiting here means login
  /// itself, and reaching the picker with at least a local default profile,
  /// never depends on the backend responding at all — ProfileProvider's own
  /// notifyListeners() calls (from loadForAccount/createProfile) are what
  /// update the picker once this finishes, whether that's near-instant
  /// (local-only) or however long the network actually takes.
  void _connectBackendAndProfiles() {
    unawaited(_syncBackendAndProfiles());
  }

  Future<void> _syncBackendAndProfiles() async {
    // Local profile/favorites/history bootstrap must never wait on the
    // network — see _loadOrCreateLocalAccountId's doc comment.
    _accountId = await _loadOrCreateLocalAccountId();

    // Reuse a still-valid token from a previous launch instead of
    // registering again — see the token-cache block above for why this
    // matters well beyond saving a round trip.
    final cachedToken = await _readCachedDeviceToken();
    if (cachedToken != null) {
      _deviceToken = cachedToken;
      _backendError = null;
    } else {
      try {
        final result = await BackendApiService().register(
          deviceId: DeviceIdService.getOrCreate(),
          deviceName: await DeviceInfoService.getDeviceModelName(),
          platform: _platformName,
        );
        _deviceToken = result.deviceToken;
        _backendError = null;
        await _cacheDeviceToken(result.deviceToken, result.expiresAt);

        // One-time bridge: fold in any data that already exists under the
        // old credential-derived account (pre-anonymous-accounts installs),
        // so switching to this scheme doesn't strand existing users' synced
        // history. Best-effort — a brand-new install has nothing to find,
        // and any failure here must never block using the app.
        if (_serverUrl.isNotEmpty && _username.isNotEmpty) {
          try {
            await BackendApiService().migrateLegacyAccount(
              result.deviceToken,
              serverUrl: _serverUrl,
              username: _username,
            );
          } catch (e) {
            debugPrint('[AuthProvider] legacy account migration failed (non-fatal): $e');
          }
        }
      } on BackendApiException catch (e) {
        _deviceToken = null;
        _backendError = '${e.code}: ${e.message}';
        debugPrint('[AuthProvider] backend connect failed (non-fatal): $e');
      } catch (e) {
        // Anything other than a BackendApiException — device id/info
        // lookup, a plugin failure, whatever — was previously uncaught
        // here, which aborted this whole function before
        // SyncManager/profileProvider below ever ran. That looked exactly
        // like "the backend never connects" even though the network call
        // itself was never reached, and on real device hardware (less
        // uniform than an emulator) is a more plausible trigger than it
        // sounds. Same non-fatal handling as a real backend failure: log
        // it, keep going on local profiles.
        _deviceToken = null;
        _backendError = '${e.runtimeType}: $e';
        debugPrint('[AuthProvider] backend connect failed (non-fatal): $e');
      }
    }

    SyncManager.instance.updateSession(
      accountId: _accountId,
      deviceToken: _deviceToken,
    );
    await profileProvider.loadForAccount(_accountId!, _deviceToken);
    await _ensureProfileExists();
  }

  /// Creates the first profile for a brand-new account, or restores the
  /// last-used one. Split out of [_syncBackendAndProfiles] so the
  /// cached-token fast path runs exactly the same bootstrap as the
  /// fresh-login path.
  Future<void> _ensureProfileExists() async {
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
          _accountId!,
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

  /// Requests a short-lived pairing code for the current device's backend
  /// account, to be typed into a second device's [joinSyncAccount] so it
  /// sees this device's profiles/favorites/history. Returns null if the
  /// backend isn't reachable or this device hasn't registered with it yet —
  /// callers (the Settings pairing UI) should show that as "sync
  /// unavailable right now", not as an error dialog.
  Future<BackendPairingCode?> createSyncPairingCode() async {
    final token = _deviceToken;
    if (token == null) return null;
    try {
      return await BackendApiService().createPairingCode(token);
    } catch (e) {
      debugPrint('[AuthProvider] createSyncPairingCode failed: $e');
      return null;
    }
  }

  /// Joins the backend account a pairing code was issued for — this
  /// device's *existing* backend account is abandoned (its device row is
  /// moved, not merged; see backend/api/account/join.php) and profiles are
  /// reloaded from the target account. Returns true on success.
  ///
  /// Note this only affects the backend-synced account, not
  /// [_loadOrCreateLocalAccountId]'s local partition key — the freshly
  /// pulled remote profiles are written into this device's existing local
  /// partition (via profileProvider.loadForAccount below), which is correct
  /// as long as this device had no meaningful local-only profiles of its
  /// own before pairing. A device that already had real local data before
  /// joining a different account is an edge case the Settings pairing UI
  /// should warn about, not something to silently overwrite.
  /// Returns null on success, or a user-facing error message on failure —
  /// deliberately not a bare bool: a 500 from a server-side bug and a
  /// genuinely wrong/expired code both used to collapse to the same
  /// generic "Invalid or expired code" text client-side, which made a real
  /// server misconfiguration indistinguishable from user error and cost
  /// real debugging time once. The raw BackendApiException code/message is
  /// safe to show directly — see json_error's doc comment in the backend.
  Future<String?> joinSyncAccount(String code) async {
    final token = _deviceToken;
    if (token == null) return 'Not connected to the sync backend yet.';
    try {
      final result = await BackendApiService().joinAccount(token, code);
      _deviceToken = result.deviceToken;
      _backendError = null;
      await _cacheDeviceToken(result.deviceToken, result.expiresAt);
      SyncManager.instance.updateSession(
        accountId: _accountId,
        deviceToken: _deviceToken,
      );
      await profileProvider.loadForAccount(_accountId!, _deviceToken);
      notifyListeners();
      return null;
    } on BackendApiException catch (e) {
      debugPrint('[AuthProvider] joinSyncAccount failed: ${e.code}: ${e.message}');
      return e.message;
    } catch (e) {
      debugPrint('[AuthProvider] joinSyncAccount failed: $e');
      return 'Something went wrong. Please try again.';
    }
  }

  /// Authenticates against the real Xtream server.
  Future<XtreamUser> _authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
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
        _connectBackendAndProfiles();
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
      _connectBackendAndProfiles();

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
      // Only a permanent delete forgets this playlist's backend identity —
      // playlistId (and so the token-cache key) is deterministic from
      // server_url+username, so a plain logout/re-login to the SAME
      // playlist must keep it cached. Clearing it unconditionally here used
      // to force a fresh register() on next login, which mints a brand-new,
      // disconnected anonymous account and made every "log out, log back
      // in" look exactly like "my sync/history disappeared" even though
      // nothing was actually lost server-side — the old account was just
      // orphaned and a new empty one silently took its place.
      await _clearCachedDeviceToken();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('local_account_id_$playlistId');
      } catch (_) {}
    }

    // Clear active playlist status
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_url');
    await prefs.remove('active_username');

    _user = null;
    _isAuthenticated = false;
    _accountId = null;
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
