/// Data models for Xtream Codes API responses
library;

import 'dart:convert';

class XtreamCategory {
  final String categoryId;
  final String categoryName;
  final int parentId;

  XtreamCategory({
    required this.categoryId,
    required this.categoryName,
    required this.parentId,
  });

  factory XtreamCategory.fromJson(Map<String, dynamic> json) {
    return XtreamCategory(
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? 'Unknown',
      parentId: int.tryParse(json['parent_id']?.toString() ?? '0') ?? 0,
    );
  }
}

class XtreamLiveStream {
  final int streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final int num;
  final String epgChannelId;
  final bool tvArchive;
  final String directSource;

  XtreamLiveStream({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    required this.num,
    this.epgChannelId = '',
    this.tvArchive = false,
    this.directSource = '',
  });

  factory XtreamLiveStream.fromJson(Map<String, dynamic> json) {
    return XtreamLiveStream(
      streamId: int.tryParse(json['stream_id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      streamIcon: json['stream_icon']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      num: int.tryParse(json['num']?.toString() ?? '0') ?? 0,
      epgChannelId: json['epg_channel_id']?.toString() ?? '',
      tvArchive: (json['tv_archive'] == 1 || json['tv_archive'] == true),
      directSource: json['direct_source']?.toString() ?? '',
    );
  }

  /// Some panels (and our own demo mode) provide a ready-to-play URL
  /// directly rather than expecting the standard Xtream path to be built —
  /// honor it when present instead of constructing `.../live/user/pass/id.m3u8`.
  String streamUrl(String baseUrl, String username, String password) {
    if (directSource.isNotEmpty) return directSource;
    return '$baseUrl/live/$username/$password/$streamId.m3u8';
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'name': name,
      'stream_icon': streamIcon,
      'category_id': categoryId,
      'num': num,
      'epg_channel_id': epgChannelId,
      'tv_archive': tvArchive ? 1 : 0,
    };
  }
}

/// One "now/next" entry from Xtream's `get_short_epg`. Not every panel
/// carries EPG data for every channel, so callers should treat an empty
/// list as normal rather than an error.
class XtreamEpgListing {
  final String title;
  final String description;
  final DateTime? start;
  final DateTime? end;
  final bool nowPlaying;

  XtreamEpgListing({
    required this.title,
    required this.description,
    this.start,
    this.end,
    this.nowPlaying = false,
  });

  // Xtream sends EPG text fields base64-encoded; fall back to the raw value
  // for the (rarer) panels that don't actually encode it.
  static String _decodeText(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    try {
      return utf8.decode(base64.decode(raw));
    } catch (_) {
      return raw;
    }
  }

  static DateTime? _decodeTimestamp(dynamic value) {
    final seconds = int.tryParse(value?.toString() ?? '');
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  factory XtreamEpgListing.fromJson(Map<String, dynamic> json) {
    return XtreamEpgListing(
      title: _decodeText(json['title']),
      description: _decodeText(json['description']),
      start: _decodeTimestamp(json['start_timestamp']),
      end: _decodeTimestamp(json['stop_timestamp']),
      nowPlaying: json['now_playing']?.toString() == '1',
    );
  }

  /// Fraction of the program elapsed so far, or null if the panel didn't
  /// provide usable start/end times.
  double? get progress {
    final s = start, e = end;
    if (s == null || e == null) return null;
    final totalSeconds = e.difference(s).inSeconds;
    if (totalSeconds <= 0) return null;
    final elapsedSeconds = DateTime.now().difference(s).inSeconds;
    return (elapsedSeconds / totalSeconds).clamp(0.0, 1.0);
  }
}

class XtreamVodStream {
  final int streamId;
  final String name;
  final String streamIcon;
  final String categoryId;
  final String containerExtension;
  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String releaseDate;
  final String rating;
  final double rating5based;
  final String added;
  final int num;
  final String customSid;
  final String directSource;

  XtreamVodStream({
    required this.streamId,
    required this.name,
    required this.streamIcon,
    required this.categoryId,
    required this.containerExtension,
    this.plot = '',
    this.cast = '',
    this.director = '',
    this.genre = '',
    this.releaseDate = '',
    this.rating = '',
    this.rating5based = 0.0,
    this.added = '',
    this.num = 0,
    this.customSid = '',
    this.directSource = '',
  });

  factory XtreamVodStream.fromJson(Map<String, dynamic> json) {
    return XtreamVodStream(
      num: int.tryParse(json['num']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      streamId: int.tryParse(json['stream_id']?.toString() ?? '0') ?? 0,
      streamIcon: json['stream_icon']?.toString() ?? '',
      rating: json['rating']?.toString() ?? '',
      rating5based:
          double.tryParse(json['rating_5based']?.toString() ?? '0') ?? 0.0,
      added: json['added']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      containerExtension: json['container_extension']?.toString() ?? '',
      customSid: json['custom_sid']?.toString() ?? '',
      directSource: json['direct_source']?.toString() ?? '',
      plot: json['plot']?.toString() ?? '',
      cast: json['cast']?.toString() ?? '',
      director: json['director']?.toString() ?? '',
      genre: json['genre']?.toString() ?? '',
      releaseDate: json['releaseDate']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'num': num,
      'name': name,
      'stream_id': streamId,
      'stream_icon': streamIcon,
      'rating': rating,
      'rating_5based': rating5based,
      'added': added,
      'category_id': categoryId,
      'container_extension': containerExtension,
      'custom_sid': customSid,
      'direct_source': directSource,
      'plot': plot,
      'cast': cast,
      'director': director,
      'genre': genre,
      'releaseDate': releaseDate,
    };
  }

  /// Honors a provided direct URL (real panels sometimes set this; our demo
  /// mode always does) instead of building the standard Xtream VOD path.
  String streamUrl(String baseUrl, String username, String password) {
    if (directSource.isNotEmpty) return directSource;
    final ext = containerExtension.isNotEmpty ? containerExtension : 'mp4';
    return '$baseUrl/movie/$username/$password/$streamId.$ext';
  }
}

class XtreamVodInfo {
  final XtreamVodStream movieData;
  final String duration;

  XtreamVodInfo({required this.movieData, this.duration = ''});

  factory XtreamVodInfo.fromJson(Map<String, dynamic> json) {
    final info = json['info'] as Map<String, dynamic>? ?? {};
    final movieDataJson = json['movie_data'] as Map<String, dynamic>? ?? {};

    // Merge info into movieDataJson to parse it as XtreamVodStream
    final merged = Map<String, dynamic>.from(movieDataJson);
    merged['stream_icon'] = info['movie_image'] ?? movieDataJson['stream_icon'];
    merged['plot'] = info['plot'] ?? movieDataJson['plot'];
    merged['cast'] = info['cast'] ?? movieDataJson['cast'];
    merged['director'] = info['director'] ?? movieDataJson['director'];
    merged['genre'] = info['genre'] ?? movieDataJson['genre'];
    merged['releaseDate'] =
        info['releasedate'] ??
        info['releaseDate'] ??
        movieDataJson['releaseDate'];
    merged['rating'] = info['rating'] ?? movieDataJson['rating'];

    return XtreamVodInfo(
      movieData: XtreamVodStream.fromJson(merged),
      duration: info['duration']?.toString() ?? '',
    );
  }
}

class XtreamSeries {
  final int seriesId;
  final String name;
  final String cover;
  final String categoryId;
  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String releaseDate;
  final String rating;
  final int lastModified;

  XtreamSeries({
    required this.seriesId,
    required this.name,
    required this.cover,
    required this.categoryId,
    this.plot = '',
    this.cast = '',
    this.director = '',
    this.genre = '',
    this.releaseDate = '',
    this.rating = '',
    this.lastModified = 0,
  });

  factory XtreamSeries.fromJson(Map<String, dynamic> json) {
    return XtreamSeries(
      seriesId: int.tryParse(json['series_id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      plot: json['plot']?.toString() ?? '',
      cast: json['cast']?.toString() ?? '',
      director: json['director']?.toString() ?? '',
      genre: json['genre']?.toString() ?? '',
      releaseDate: json['releaseDate']?.toString() ?? '',
      rating: json['rating']?.toString() ?? '',
      lastModified: int.tryParse(json['last_modified']?.toString() ?? '0') ?? 0,
    );
  }
}

class XtreamEpisode {
  final String id;
  final int episodeNum;
  final String title;
  final String containerExtension;
  final String info;
  final String customSid;
  final int added;
  final int season;
  final String directSource;

  XtreamEpisode({
    required this.id,
    required this.episodeNum,
    required this.title,
    required this.containerExtension,
    this.info = '',
    this.customSid = '',
    this.added = 0,
    required this.season,
    this.directSource = '',
  });

  factory XtreamEpisode.fromJson(Map<String, dynamic> json) {
    return XtreamEpisode(
      id: json['id']?.toString() ?? '',
      episodeNum: int.tryParse(json['episode_num']?.toString() ?? '0') ?? 0,
      title: json['title']?.toString() ?? '',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
      info: json['info']?.toString() ?? '',
      customSid: json['custom_sid']?.toString() ?? '',
      added: int.tryParse(json['added']?.toString() ?? '0') ?? 0,
      season: int.tryParse(json['season']?.toString() ?? '0') ?? 0,
      directSource: json['direct_source']?.toString() ?? '',
    );
  }

  /// See [XtreamVodStream.streamUrl] — same direct-URL override, used by our
  /// demo mode to point at real test streams instead of a fake Xtream path.
  String streamUrl(String baseUrl, String username, String password) {
    if (directSource.isNotEmpty) return directSource;
    final ext = containerExtension.isNotEmpty ? containerExtension : 'mp4';
    return '$baseUrl/series/$username/$password/$id.$ext';
  }
}

class XtreamSeriesInfo {
  final XtreamSeries info;
  final Map<int, List<XtreamEpisode>> episodes; // season -> episodes

  XtreamSeriesInfo({required this.info, required this.episodes});

  factory XtreamSeriesInfo.fromJson(Map<String, dynamic> json) {
    final infoJson = json['info'] as Map<String, dynamic>? ?? {};
    // Extract series info mapping slightly differently from get_series_info
    final info = XtreamSeries(
      seriesId: int.tryParse(infoJson['series_id']?.toString() ?? '0') ?? 0,
      name: infoJson['name']?.toString() ?? '',
      cover: infoJson['cover']?.toString() ?? '',
      categoryId: infoJson['category_id']?.toString() ?? '',
      plot: infoJson['plot']?.toString() ?? '',
      cast: infoJson['cast']?.toString() ?? '',
      director: infoJson['director']?.toString() ?? '',
      genre: infoJson['genre']?.toString() ?? '',
      releaseDate: infoJson['releaseDate']?.toString() ?? '',
      rating: infoJson['rating']?.toString() ?? '',
    );

    final episodesMap = <int, List<XtreamEpisode>>{};
    final epsJson = json['episodes'];
    if (epsJson is Map) {
      epsJson.forEach((seasonStr, seasonEps) {
        final seasonNum = int.tryParse(seasonStr.toString()) ?? 0;
        if (seasonEps is List) {
          episodesMap[seasonNum] = seasonEps
              .map((e) => XtreamEpisode.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      });
    }

    return XtreamSeriesInfo(info: info, episodes: episodesMap);
  }
}
