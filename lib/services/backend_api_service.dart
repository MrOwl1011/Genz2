import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/backend_config.dart';
import '../core/datetime_utils.dart';

/// Thrown for every backend call failure. [retryable] distinguishes network/
/// timeout/5xx/429 failures (worth keeping in a sync queue and retrying
/// later) from 4xx business-logic rejections like invalid credentials or a
/// profile limit (retrying those without the user changing something would
/// just fail again) — the sync engine (a later phase) relies on this
/// distinction to decide whether to keep a queued mutation or drop it.
class BackendApiException implements Exception {
  final String code;
  final String message;
  final bool retryable;

  BackendApiException(this.code, this.message, {this.retryable = false});

  @override
  String toString() => message;
}

class BackendAccountResult {
  final String accountId;
  final String deviceToken;
  final DateTime expiresAt;
  final List<Map<String, dynamic>> profiles;

  BackendAccountResult({
    required this.accountId,
    required this.deviceToken,
    required this.expiresAt,
    required this.profiles,
  });
}

/// Deliberately not a [BackendAccountResult]: merge.php issues no new
/// token, so there is no device_token or expiry to report — the caller
/// keeps authenticating with the token it already holds.
class BackendMergeResult {
  final String accountId;
  final List<Map<String, dynamic>> profiles;

  /// How many profiles came across from the previous account.
  final int mergedProfiles;

  /// Only ever nonzero when the target was already at the profile cap and a
  /// non-colliding profile had nowhere to go; it stays on the old account.
  final int profilesLeftBehind;

  BackendMergeResult({
    required this.accountId,
    required this.profiles,
    required this.mergedProfiles,
    required this.profilesLeftBehind,
  });
}

class BackendPairingCode {
  final String code;
  final DateTime expiresAt;

  BackendPairingCode({required this.code, required this.expiresAt});
}

/// Talks to the PHP backend in backend/ — modeled directly on
/// XtreamApiService's shape (singleton, http package, bounded timeout,
/// manual JSON parsing/exception throwing) so anyone familiar with that
/// service recognizes this one immediately.
class BackendApiService {
  static final BackendApiService _instance = BackendApiService._internal();
  factory BackendApiService() => _instance;
  BackendApiService._internal();

  // Generous on purpose: every caller here already treats backend failure
  // as non-fatal and runs it unawaited (see AuthProvider._connectBackendAndProfiles),
  // so a longer timeout never blocks the UI — it only gives real but slow/
  // lossy connections (seen in the wild on TV boxes over a mobile hotspot:
  // ~400ms RTT with ~25% packet loss, enough to blow past a 15s budget on
  // its own, especially once a TLS handshake's extra round trips are in
  // the mix) more room to actually finish instead of giving up early.
  static const Duration _timeout = Duration(seconds: 30);

  // ─── HTTPS client ───────────────────────────────────────────────────────
  //
  // The backend's certificate chains up to "SSL.com TLS RSA Root CA 2022".
  // That root was created in 2022, so it simply does not exist in the CA
  // store of anything that shipped before it and never got a trust-store
  // update — which is exactly the situation on cheap Android TV hardware.
  // A MediaTek set running Android 11 (2020) failed every backend call with
  //
  //     CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate
  //
  // while iOS and current Android phones were fine, because Apple and
  // Google push CA updates and that TV never will. The server is not
  // misconfigured — it does send the intermediate — the device's trust
  // store is just too old to contain the root the chain terminates at.
  //
  // So the app carries that one root itself. `withTrustedRoots: true` keeps
  // the platform's own CAs as well, so this only ever *adds* an anchor:
  // certificate verification stays fully on, and everything else continues
  // to validate exactly as before. This is deliberately not a
  // badCertificateCallback, which would have "fixed" it by disabling
  // verification and handing anyone on the network a free MITM.
  static http.Client? _cachedClient;

  Future<http.Client> _httpClient() async {
    final existing = _cachedClient;
    if (existing != null) return existing;

    final context = SecurityContext(withTrustedRoots: true);
    try {
      final pem = await rootBundle.load(
        'assets/certs/ssl_com_tls_rsa_root_2022.pem',
      );
      context.setTrustedCertificatesBytes(pem.buffer.asUint8List());
    } catch (_) {
      // Asset missing/unreadable: fall through with just the platform
      // roots. Devices whose trust store already has this root keep
      // working; nothing becomes less secure.
    }

    final client = IOClient(
      HttpClient(context: context)..connectionTimeout = _timeout,
    );
    _cachedClient = client;
    return client;
  }

  Map<String, String> _headers({String? token}) => {
    'Content-Type': 'application/json',
    'X-Api-Key': BackendConfig.apiKey,
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}$path');

    // One retry on a pure network failure (timeout, DNS hiccup, dropped
    // connection) — cheap insurance against a single transient packet-loss
    // event on a bad connection (e.g. a TV on a lossy mobile hotspot)
    // costing an otherwise-successful sync. Not retried: a response that
    // came back at all (4xx/5xx) — that's handled below, not here.
    final client = await _httpClient();
    http.Response response;
    try {
      response = await client
          .post(
            uri,
            headers: _headers(token: token),
            body: json.encode(body),
          )
          .timeout(_timeout);
    } catch (_) {
      try {
        response = await client
            .post(
              uri,
              headers: _headers(token: token),
              body: json.encode(body),
            )
            .timeout(_timeout);
      } catch (e) {
        // Include the underlying exception. It used to be swallowed
        // entirely, which meant a device that couldn't sync reported only
        // "could not reach the sync server" — indistinguishable between a
        // DNS failure, a TLS handshake rejection and a plain timeout, and
        // impossible to diagnose remotely on a TV with no debugger
        // attached. The type/message is what actually names the cause.
        throw BackendApiException(
          'NETWORK_ERROR',
          'Could not reach the sync server (${e.runtimeType}: $e).',
          retryable: true,
        );
      }
    }

    Map<String, dynamic> decoded;
    try {
      decoded = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw BackendApiException(
        'INVALID_RESPONSE',
        'The sync server returned an invalid response.',
        retryable: response.statusCode >= 500,
      );
    }

    if (decoded['success'] == true) {
      final data = decoded['data'];
      return data is Map ? Map<String, dynamic>.from(data) : {};
    }

    final error = decoded['error'];
    final code =
        (error is Map ? error['code']?.toString() : null) ?? 'UNKNOWN_ERROR';
    final message =
        (error is Map ? error['message']?.toString() : null) ??
        'Something went wrong.';
    final retryable = response.statusCode >= 500 || response.statusCode == 429;
    throw BackendApiException(code, message, retryable: retryable);
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return [];
    return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ─── Account ────────────────────────────────────────────────────────────────
  //
  // Deliberately nothing here ever sends an Xtream server_url, username or
  // password — see register.php's doc comment. This backend identifies a
  // sync account purely by an opaque, server-generated account_id; it has
  // no way to connect that id to any IPTV service, which is the whole
  // reason it exists as a separate concept from XtreamApiService.

  /// Registers this device and returns the account it belongs to.
  ///
  /// With an [accountKey] (derived from the user's IPTV credentials — see
  /// AccountKey), this resolves to the same account on every device those
  /// credentials are used on, which is what makes profiles and history sync
  /// with no pairing step. First use creates it; later uses just attach
  /// this device to it.
  ///
  /// With neither key nor code, this is a brand-new empty anonymous
  /// account — a fresh install that hasn't signed into a panel yet.
  ///
  /// [pairingCode] is the superseded path, still accepted so app versions
  /// released before keys existed keep working. An invalid/expired code is
  /// not an error: the backend falls back to a new account rather than
  /// failing the whole registration over a typo.
  Future<BackendAccountResult> register({
    required String deviceId,
    required String deviceName,
    required String platform,
    String? pairingCode,
    String? accountKey,
  }) async {
    final data = await _post('/api/account/register.php', {
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
      if (pairingCode != null && pairingCode.isNotEmpty)
        'pairing_code': pairingCode,
      if (accountKey != null && accountKey.isNotEmpty) 'account_key': accountKey,
    });

    return BackendAccountResult(
      accountId: data['account_id'] as String,
      deviceToken: data['device_token'] as String,
      expiresAt: parseBackendUtc(data['expires_at'] as String),
      profiles: _asMapList(data['profiles']),
    );
  }

  /// Folds the account this device *used* to be on into the one it is on
  /// now, bringing its profiles, favorites and history across.
  ///
  /// Two callers, one operation: the one-time migration off the old
  /// anonymous accounts, and the case where a user's IPTV password changed
  /// so their derived key (and therefore their account) changed with it.
  /// Requires holding tokens for both accounts, which is the proof of
  /// ownership that replaces a pairing code — see merge.php.
  ///
  /// Safe to retry: merging an already-merged account is a no-op.
  Future<BackendMergeResult> mergeAccount({
    required String token,
    required String previousToken,
  }) async {
    final data = await _post('/api/account/merge.php', {
      'previous_token': previousToken,
    }, token: token);

    return BackendMergeResult(
      accountId: data['account_id'] as String,
      profiles: _asMapList(data['profiles']),
      mergedProfiles: (data['merged_profiles'] as num?)?.toInt() ?? 0,
      profilesLeftBehind: (data['profiles_left_behind'] as num?)?.toInt() ?? 0,
    );
  }

  /// A code this device's account can be joined from another device — see
  /// pairing.php. Shown to the user in Settings; multi-use for 15 minutes,
  /// so one code shown once can add several devices.
  Future<BackendPairingCode> createPairingCode(String token) async {
    final data = await _post('/api/account/pairing_code.php', {}, token: token);
    return BackendPairingCode(
      code: data['code'] as String,
      expiresAt: parseBackendUtc(data['expires_at'] as String),
    );
  }

  /// Moves this already-registered device onto the account [code] was
  /// issued for — the "I got a code after I'd already opened the app"
  /// path. See join.php for what this does and does not carry over.
  Future<BackendAccountResult> joinAccount(String token, String code) async {
    final data = await _post('/api/account/join.php', {
      'code': code,
    }, token: token);

    return BackendAccountResult(
      accountId: data['account_id'] as String,
      deviceToken: data['device_token'] as String,
      expiresAt: parseBackendUtc(data['expires_at'] as String),
      profiles: _asMapList(data['profiles']),
    );
  }

  /// One-time bridge for an install that used the old
  /// credential-derived account scheme before this backend stopped storing
  /// Xtream credentials — see migrate_legacy.php. [serverUrl]/[username] are
  /// sent here, and only here, purely to locate that old account; nothing
  /// persists them. Returns `migrated: false` (not an error) for any
  /// install that never had a legacy account to begin with, which is the
  /// common case going forward.
  Future<bool> migrateLegacyAccount(
    String token, {
    required String serverUrl,
    required String username,
  }) async {
    final data = await _post('/api/account/migrate_legacy.php', {
      'server_url': serverUrl,
      'username': username,
    }, token: token);
    return data['migrated'] == true;
  }

  // ─── Profiles ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listProfiles(String token) async {
    final data = await _post('/api/profiles/list.php', {}, token: token);
    return _asMapList(data['profiles']);
  }

  Future<Map<String, dynamic>> createProfile(
    String token, {
    required String profileId,
    required String name,
    required String avatar,
    required bool isKids,
    required DateTime updatedAt,
  }) async {
    final data = await _post('/api/profiles/create.php', {
      'profile_id': profileId,
      'name': name,
      'avatar': avatar,
      'is_kids': isKids,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }, token: token);
    return Map<String, dynamic>.from(data['profile'] as Map);
  }

  Future<Map<String, dynamic>> updateProfile(
    String token, {
    required String profileId,
    String? name,
    String? avatar,
    bool? isKids,
    required DateTime updatedAt,
  }) async {
    final data = await _post('/api/profiles/update.php', {
      'profile_id': profileId,
      'name': ?name,
      'avatar': ?avatar,
      'is_kids': ?isKids,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }, token: token);
    return Map<String, dynamic>.from(data['profile'] as Map);
  }

  Future<void> deleteProfile(String token, String profileId) async {
    await _post('/api/profiles/delete.php', {
      'profile_id': profileId,
    }, token: token);
  }

  // ─── Favorites ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getFavorites(
    String token,
    String profileId,
  ) async {
    final data = await _post('/api/favorites/get.php', {
      'profile_id': profileId,
    }, token: token);
    return _asMapList(data['favorites']);
  }

  Future<void> addFavorite(
    String token, {
    required String profileId,
    required String streamId,
    required String streamType,
    required String title,
    String? posterUrl,
    Map<String, dynamic>? rawData,
    required DateTime updatedAt,
  }) async {
    await _post('/api/favorites/add.php', {
      'profile_id': profileId,
      'stream_id': streamId,
      'stream_type': streamType,
      'title': title,
      'poster_url': posterUrl,
      'raw_data': rawData,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }, token: token);
  }

  Future<void> removeFavorite(
    String token, {
    required String profileId,
    required String streamId,
    required String streamType,
  }) async {
    await _post('/api/favorites/remove.php', {
      'profile_id': profileId,
      'stream_id': streamId,
      'stream_type': streamType,
    }, token: token);
  }

  // ─── History ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getHistory(
    String token,
    String profileId,
  ) async {
    final data = await _post('/api/history/get.php', {
      'profile_id': profileId,
    }, token: token);
    return _asMapList(data['history']);
  }

  Future<void> saveHistory(
    String token, {
    required String profileId,
    required String streamId,
    required String streamType,
    String? episodeId,
    String? seriesId,
    required String title,
    String? posterUrl,
    required int positionSeconds,
    required int durationSeconds,
    Map<String, dynamic>? rawData,
    required DateTime updatedAt,
  }) async {
    await _post('/api/history/save.php', {
      'profile_id': profileId,
      'stream_id': streamId,
      'stream_type': streamType,
      'episode_id': episodeId,
      'series_id': seriesId,
      'title': title,
      'poster_url': posterUrl,
      'position_seconds': positionSeconds,
      'duration_seconds': durationSeconds,
      'raw_data': rawData,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }, token: token);
  }

  // ─── Devices ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listDevices(String token) async {
    final data = await _post('/api/devices/list.php', {}, token: token);
    return _asMapList(data['devices']);
  }

  Future<void> removeDevice(String token, String deviceId) async {
    await _post('/api/devices/remove.php', {
      'device_id': deviceId,
    }, token: token);
  }
}
