import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import '../models/xtream_models.dart';

/// Top-level so it can be handed to [compute] — an isolate entry point
/// cannot be a closure or an instance method.
dynamic _decodeJson(String body) => json.decode(body);

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
    final maxConn =
        int.tryParse(userInfo['max_connections']?.toString() ?? '0') ?? 0;
    final activeConn =
        int.tryParse(userInfo['active_cons']?.toString() ?? '0') ?? 0;
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
    if (!cleanedUrl.startsWith('http://') &&
        !cleanedUrl.startsWith('https://')) {
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
        final message =
            userInfo['message']?.toString() ?? 'Invalid username or password';
        throw Exception(message);
      }
      return XtreamUser.fromJson(data);
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception(
          'Connection failed. Please check the Server URL and your network.',
        );
      }
      if (e is FormatException) {
        // The panel returned a 200 with a non-JSON body — an HTML block/
        // rate-limit page from the panel or a proxy in front of it is the
        // common real-world cause, not literally malformed JSON. Without
        // this, the raw FormatException ("Unexpected character (at
        // character 1)\n<meta name=\"viewport\"...") surfaced straight to
        // the UI, mangled further by callers that blindly strip a leading
        // "Exception: " (turning "FormatException: ..." into
        // "FormatUnexpected character...").
        throw Exception(
          "This server didn't return a valid response. It may be down, "
          'blocking this connection, or the Server URL may be wrong. '
          'Check the address and try again.',
        );
      }
      rethrow;
    }
  }

  // ─── Generic API Request ─────────────────────────────────────────────────────

  /// Parses a response body, moving the work to a background isolate once
  /// it is big enough to be worth the hand-off.
  ///
  /// `json.decode` is pure CPU work on whatever isolate calls it, so doing
  /// it inline ran it on the UI isolate. That is invisible on a phone, but
  /// Xtream list endpoints routinely return hundreds of KB (a full category
  /// of movies, a series with every episode), and on TV-box silicon parsing
  /// that costs seconds, not milliseconds — during which the isolate cannot
  /// service input or paint. An ANR trace from a MediaTek set caught exactly
  /// this: the main thread pinned in Dart AOT code with ~39s of accumulated
  /// CPU time, the system reporting "Waited 9750ms for KeyEvent", which is
  /// what "I pressed a movie and it froze, then died" actually was. Several
  /// category rows each decoding their own payload compounds it.
  ///
  /// Small bodies stay inline: spawning an isolate costs more than parsing
  /// a few KB, and most calls here are small.
  static Future<dynamic> _decodeBody(String body) {
    if (body.length < _isolateDecodeThreshold) {
      return Future.value(json.decode(body));
    }
    return compute(_decodeJson, body);
  }

  /// Bodies at or above this size are parsed off the UI isolate.
  static const int _isolateDecodeThreshold = 32 * 1024;

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
    final uri = Uri.parse(
      normalizeUrl(serverUrl),
    ).replace(queryParameters: params);
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }
      return await _decodeBody(response.body);
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception('Network error. Please check your connection.');
      }
      if (e is FormatException) {
        // See authenticate()'s identical catch above for the full
        // reasoning — this is the one that was actually firing for the
        // reported bug, since every content list call goes through here.
        throw Exception(
          "This server didn't return a valid response. It may be down, "
          'blocking this connection, or the Server URL may be wrong. '
          'Check the address and try again.',
        );
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
    return data
        .map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>))
        .toList();
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
    return data
        .map((e) => XtreamLiveStream.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// "Now/next" program info for one channel, if the panel carries EPG data
  /// for it — many don't, so an empty result here is a normal, non-error
  /// outcome for callers to just skip decorating the UI with.
  Future<List<XtreamEpgListing>> getShortEpg({
    required String serverUrl,
    required String username,
    required String password,
    required int streamId,
    int limit = 2,
  }) async {
    final data = await _apiRequest(
      serverUrl: serverUrl,
      username: username,
      password: password,
      action: 'get_short_epg',
      extra: {'stream_id': streamId.toString(), 'limit': limit.toString()},
    );
    final listings = data is Map ? data['epg_listings'] : data;
    if (listings is! List) return [];
    return listings
        .whereType<Map>()
        .map((e) => XtreamEpgListing.fromJson(e.cast<String, dynamic>()))
        .toList();
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
    return data
        .map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>))
        .toList();
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
    return data
        .map((e) => XtreamVodStream.fromJson(e as Map<String, dynamic>))
        .toList();
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
    return data
        .map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>))
        .toList();
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
    return data
        .map((e) => XtreamSeries.fromJson(e as Map<String, dynamic>))
        .toList();
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
