import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/xtream_models.dart';

class XtreamUser {
  final String username;
  final String status;
  final DateTime? expiryDate;
  final int maxConnections;
  final int activeConnections;
  final List<String> allowedOutputs;

  XtreamUser({
    required this.username,
    required this.status,
    required this.expiryDate,
    required this.maxConnections,
    required this.activeConnections,
    required this.allowedOutputs,
  });

  factory XtreamUser.fromJson(Map<String, dynamic> json) {
    final userInfo = json['user_info'] as Map<String, dynamic>? ?? {};
    DateTime? expDate;
    final expStr = userInfo['exp_date'];
    if (expStr != null) {
      final seconds = int.tryParse(expStr.toString());
      if (seconds != null) {
        expDate = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }
    final maxConn = int.tryParse(userInfo['max_connections']?.toString() ?? '0') ?? 0;
    final activeConn = int.tryParse(userInfo['active_cons']?.toString() ?? '0') ?? 0;
    final outputs = List<String>.from(userInfo['allowed_outputs'] ?? []);

    return XtreamUser(
      username: userInfo['username']?.toString() ?? '',
      status: userInfo['status']?.toString() ?? 'Unknown',
      expiryDate: expDate,
      maxConnections: maxConn,
      activeConnections: activeConn,
      allowedOutputs: outputs,
    );
  }
}

class XtreamApiService {
  static final XtreamApiService _instance = XtreamApiService._internal();
  factory XtreamApiService() => _instance;
  XtreamApiService._internal();

  // ─── URL Helpers ────────────────────────────────────────────────────────────

  /// Normalize a raw server URL to include /player_api.php
  static String normalizeUrl(String url) {
    var cleanedUrl = url.trim();
    if (!cleanedUrl.startsWith('http://') && !cleanedUrl.startsWith('https://')) {
      cleanedUrl = 'http://$cleanedUrl';
    }
    if (cleanedUrl.endsWith('/')) {
      cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
    }
    if (!cleanedUrl.endsWith('/player_api.php')) {
      cleanedUrl = '$cleanedUrl/player_api.php';
    }
    return cleanedUrl;
  }

  /// Extract the base server URL (without /player_api.php)
  static String getBaseUrl(String normalizedUrl) {
    return normalizedUrl.replaceAll('/player_api.php', '');
  }

  // ─── Authentication ──────────────────────────────────────────────────────────

  Future<XtreamUser> authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final normalizedUrl = normalizeUrl(serverUrl);
    final uri = Uri.parse(normalizedUrl).replace(
      queryParameters: {
        'username': username.trim(),
        'password': password.trim(),
      },
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }
      final dynamic data = json.decode(response.body);
      if (data is! Map<String, dynamic>) {
        throw Exception('Invalid response format from server');
      }
      final userInfo = data['user_info'] as Map<String, dynamic>?;
      if (userInfo == null) {
        throw Exception('No user info returned by the server');
      }
      final auth = userInfo['auth'];
      if (auth == null || auth == 0 || auth == '0' || auth == false) {
        final message = userInfo['message']?.toString() ?? 'Invalid username or password';
        throw Exception(message);
      }
      return XtreamUser.fromJson(data);
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception('Connection failed. Please check the Server URL and your network.');
      }
      rethrow;
    }
  }

  // ─── Generic API Request ─────────────────────────────────────────────────────

  Future<dynamic> _apiRequest({
    required String serverUrl,
    required String username,
    required String password,
    required String action,
    Map<String, String>? extra,
  }) async {
    final params = <String, String>{
      'username': username,
      'password': password,
      'action': action,
      ...?extra,
    };
    final uri = Uri.parse(normalizeUrl(serverUrl)).replace(queryParameters: params);
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }
      return json.decode(response.body);
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception('Network error. Please check your connection.');
      }
      rethrow;
    }
  }

  // ─── Live TV ─────────────────────────────────────────────────────────────────

  Future<List<XtreamCategory>> getLiveCategories({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_live_categories',
    );
    if (data is! List) return [];
    return data.map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<XtreamLiveStream>> getLiveStreams({
    required String serverUrl,
    required String username,
    required String password,
    String? categoryId,
  }) async {
    final extra = categoryId != null ? {'category_id': categoryId} : null;
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_live_streams',
      extra: extra,
    );
    if (data is! List) return [];
    return data.map((e) => XtreamLiveStream.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─── VOD (Movies) ────────────────────────────────────────────────────────────

  Future<List<XtreamCategory>> getVodCategories({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_vod_categories',
    );
    if (data is! List) return [];
    return data.map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<XtreamVodStream>> getVodStreams({
    required String serverUrl,
    required String username,
    required String password,
    String? categoryId,
  }) async {
    final extra = categoryId != null ? {'category_id': categoryId} : null;
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_vod_streams',
      extra: extra,
    );
    if (data is! List) return [];
    return data.map((e) => XtreamVodStream.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<XtreamVodInfo?> getVodInfo({
    required String serverUrl,
    required String username,
    required String password,
    required int vodId,
  }) async {
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_vod_info',
      extra: {'vod_id': vodId.toString()},
    );
    if (data is! Map<String, dynamic>) return null;
    return XtreamVodInfo.fromJson(data);
  }

  // ─── Series ───────────────────────────────────────────────────────────────────

  Future<List<XtreamCategory>> getSeriesCategories({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_series_categories',
    );
    if (data is! List) return [];
    return data.map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<XtreamSeries>> getSeriesList({
    required String serverUrl,
    required String username,
    required String password,
    String? categoryId,
  }) async {
    final extra = categoryId != null ? {'category_id': categoryId} : null;
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_series',
      extra: extra,
    );
    if (data is! List) return [];
    return data.map((e) => XtreamSeries.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<XtreamSeriesInfo?> getSeriesInfo({
    required String serverUrl,
    required String username,
    required String password,
    required int seriesId,
  }) async {
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_series_info',
      extra: {'series_id': seriesId.toString()},
    );
    if (data is! Map<String, dynamic>) return null;
    return XtreamSeriesInfo.fromJson(data);
  }
}
