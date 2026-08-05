import 'dart:convert';
import 'package:http/http.dart' as http;
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

class BackendLoginResult {
  final String accountId;
  final String deviceToken;
  final DateTime expiresAt;
  final List<Map<String, dynamic>> profiles;

  BackendLoginResult({
    required this.accountId,
    required this.deviceToken,
    required this.expiresAt,
    required this.profiles,
  });
}

/// Talks to the PHP backend in backend/ — modeled directly on
/// XtreamApiService's shape (singleton, http package, bounded timeout,
/// manual JSON parsing/exception throwing) so anyone familiar with that
/// service recognizes this one immediately.
class BackendApiService {
  static final BackendApiService _instance = BackendApiService._internal();
  factory BackendApiService() => _instance;
  BackendApiService._internal();

  static const Duration _timeout = Duration(seconds: 15);

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

    http.Response response;
    try {
      response = await http
          .post(uri, headers: _headers(token: token), body: json.encode(body))
          .timeout(_timeout);
    } catch (_) {
      throw BackendApiException(
        'NETWORK_ERROR',
        'Could not reach the sync server. Please check your connection.',
        retryable: true,
      );
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
    final code = (error is Map ? error['code']?.toString() : null) ?? 'UNKNOWN_ERROR';
    final message = (error is Map ? error['message']?.toString() : null) ?? 'Something went wrong.';
    final retryable = response.statusCode >= 500 || response.statusCode == 429;
    throw BackendApiException(code, message, retryable: retryable);
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return [];
    return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ─── Account ────────────────────────────────────────────────────────────────

  Future<BackendLoginResult> login({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    final data = await _post('/api/account/login.php', {
      'server_url': serverUrl,
      'username': username,
      'password': password,
      'device_id': deviceId,
      'device_name': deviceName,
      'platform': platform,
    });

    return BackendLoginResult(
      accountId: data['account_id'] as String,
      deviceToken: data['device_token'] as String,
      expiresAt: parseBackendUtc(data['expires_at'] as String),
      profiles: _asMapList(data['profiles']),
    );
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
      if (name != null) 'name': name,
      if (avatar != null) 'avatar': avatar,
      if (isKids != null) 'is_kids': isKids,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }, token: token);
    return Map<String, dynamic>.from(data['profile'] as Map);
  }

  Future<void> deleteProfile(String token, String profileId) async {
    await _post('/api/profiles/delete.php', {'profile_id': profileId}, token: token);
  }

  // ─── Favorites ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getFavorites(String token, String profileId) async {
    final data = await _post('/api/favorites/get.php', {'profile_id': profileId}, token: token);
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

  Future<List<Map<String, dynamic>>> getHistory(String token, String profileId) async {
    final data = await _post('/api/history/get.php', {'profile_id': profileId}, token: token);
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
    await _post('/api/devices/remove.php', {'device_id': deviceId}, token: token);
  }
}
