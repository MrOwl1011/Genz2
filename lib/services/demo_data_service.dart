import '../models/xtream_models.dart';
import 'xtream_api_service.dart';

/// Fully local mock backend used for App Store / Play Store review.
///
/// Reviewers are given the credentials below (Server: "demo" + either demo
/// account) instead of a real IPTV subscription. When those exact
/// credentials are used, [AuthProvider] and [ContentProvider] both detect it
/// via [DemoDataService.isDemoLogin] and serve everything from here instead
/// of ever making a network call to a real server — categories, listings and
/// metadata are all static in-memory data, and playback uses public, legal
/// HLS test streams so the player itself can still be exercised end to end
/// (including on iOS, where playback goes through the custom VLCKit backend
/// rather than AVPlayer — see [XtreamVodStream.streamUrl] and friends, which
/// hand these URLs straight through unmodified via `directSource`).
class DemoDataService {
  DemoDataService._();

  /// What reviewers type into the "Server" field — not a real server;
  /// matching against this hostname is what flags a login as demo mode.
  static const String kDemoServerLabel = 'demo';

  static const Map<String, String> _demoAccounts = {
    'demo': 'demo',
    'test': 'test',
  };

  /// True if [serverUrl]/[username]/[password] exactly match one of the two
  /// published demo accounts. Used to gate demo mode everywhere it matters.
  ///
  /// Compares hostname only (ignoring scheme/trailing slash/case) so
  /// reviewers land in demo mode whether they type "demo", "http://demo", or
  /// "DEMO".
  static bool isDemoLogin(String serverUrl, String username, String password) {
    final normalizedBase = XtreamApiService.getBaseUrl(
      XtreamApiService.normalizeUrl(serverUrl),
    );
    final host = Uri.tryParse(normalizedBase)?.host.toLowerCase() ?? '';
    if (host.isEmpty || host != kDemoServerLabel) return false;
    return _demoAccounts[username.trim()] == password.trim();
  }

  static XtreamUser buildDemoUser(String username) {
    return XtreamUser(
      username: username,
      status: 'Demo Mode',
      expiryDate: null, // shown as "Lifetime / Unlimited" in the UI
      maxConnections: 1,
      activeConnections: 0,
      allowedOutputs: const ['m3u8', 'ts'],
    );
  }

  // ─── Public, legal HLS test streams ─────────────────────────────────────────
  static const _hlsLiveAkamai = 'https://cph-p2p-msl.akamaized.net/hls/live/2000341/test/master.m3u8';
  static const _hlsLiveAppleBipBop =
      'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8';
  static const _hlsMux = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
  static const _hlsSintel = 'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8';
  static const _hlsTearsOfSteel =
      'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8';

  // ─── Live TV ─────────────────────────────────────────────────────────────

  static final List<XtreamCategory> _liveCategories = [
    XtreamCategory(categoryId: 'demo_live_news', categoryName: 'News', parentId: 0),
    XtreamCategory(categoryId: 'demo_live_sports', categoryName: 'Sports', parentId: 0),
    XtreamCategory(categoryId: 'demo_live_entertainment', categoryName: 'Entertainment', parentId: 0),
  ];

  static final List<XtreamLiveStream> _liveStreams = [
    XtreamLiveStream(
      streamId: 9001,
      name: 'Demo Live Channel 1',
      streamIcon: '',
      categoryId: 'demo_live_news',
      num: 1,
      directSource: _hlsLiveAkamai,
    ),
    XtreamLiveStream(
      streamId: 9002,
      name: 'Demo Live Channel 2',
      streamIcon: '',
      categoryId: 'demo_live_sports',
      num: 2,
      directSource: _hlsLiveAppleBipBop,
    ),
  ];

  // ─── Movies ──────────────────────────────────────────────────────────────

  static final List<XtreamCategory> _vodCategories = [
    XtreamCategory(categoryId: 'demo_vod_action', categoryName: 'Action', parentId: 0),
    XtreamCategory(categoryId: 'demo_vod_comedy', categoryName: 'Comedy', parentId: 0),
    XtreamCategory(categoryId: 'demo_vod_drama', categoryName: 'Drama', parentId: 0),
  ];

  static final List<XtreamVodStream> _vodStreams = [
    XtreamVodStream(
      streamId: 8001,
      name: 'Big Buck Bunny',
      streamIcon: '',
      categoryId: 'demo_vod_action',
      containerExtension: 'm3u8',
      plot: 'A sample demo movie used to preview playback in GenZ+.',
      genre: 'Animation',
      releaseDate: '2008-04-10',
      rating: '4.5',
      added: '1700000000',
      directSource: _hlsMux,
    ),
    XtreamVodStream(
      streamId: 8002,
      name: 'Sintel',
      streamIcon: '',
      categoryId: 'demo_vod_comedy',
      containerExtension: 'm3u8',
      plot: 'A sample demo movie used to preview playback in GenZ+.',
      genre: 'Drama',
      releaseDate: '2010-09-30',
      rating: '4.7',
      added: '1700000100',
      directSource: _hlsSintel,
    ),
    XtreamVodStream(
      streamId: 8003,
      name: 'Tears of Steel',
      streamIcon: '',
      categoryId: 'demo_vod_drama',
      containerExtension: 'm3u8',
      plot: 'A sample demo movie used to preview playback in GenZ+.',
      genre: 'Sci-Fi',
      releaseDate: '2012-09-26',
      rating: '4.4',
      added: '1700000200',
      directSource: _hlsTearsOfSteel,
    ),
  ];

  // ─── Series ──────────────────────────────────────────────────────────────

  static final List<XtreamCategory> _seriesCategories = [
    XtreamCategory(categoryId: 'demo_series_popular', categoryName: 'Popular Series', parentId: 0),
    XtreamCategory(categoryId: 'demo_series_kids', categoryName: 'Kids', parentId: 0),
  ];

  static final List<XtreamSeries> _seriesList = [
    XtreamSeries(
      seriesId: 7001,
      name: 'Demo Series One',
      cover: '',
      categoryId: 'demo_series_popular',
      plot: 'A sample demo series used to preview playback in GenZ+.',
      genre: 'Drama',
      releaseDate: '2020-01-01',
      rating: '4.2',
      lastModified: 1700001000,
    ),
    XtreamSeries(
      seriesId: 7002,
      name: 'Demo Series Two',
      cover: '',
      categoryId: 'demo_series_popular',
      plot: 'A sample demo series used to preview playback in GenZ+.',
      genre: 'Comedy',
      releaseDate: '2021-01-01',
      rating: '4.0',
      lastModified: 1700001100,
    ),
    XtreamSeries(
      seriesId: 7003,
      name: 'Demo Kids Show',
      cover: '',
      categoryId: 'demo_series_kids',
      plot: 'A sample demo series used to preview playback in GenZ+.',
      genre: 'Animation',
      releaseDate: '2019-01-01',
      rating: '4.6',
      lastModified: 1700001200,
    ),
  ];

  static final Map<int, XtreamSeriesInfo> _seriesInfoById = {
    7001: XtreamSeriesInfo(
      info: _seriesList[0],
      episodes: {
        1: [
          XtreamEpisode(
            id: 'demo_7001_s1e1',
            episodeNum: 1,
            title: 'Episode 1',
            containerExtension: 'm3u8',
            season: 1,
            directSource: _hlsMux,
          ),
        ],
      },
    ),
    7002: XtreamSeriesInfo(
      info: _seriesList[1],
      episodes: {
        1: [
          XtreamEpisode(
            id: 'demo_7002_s1e1',
            episodeNum: 1,
            title: 'Episode 2',
            containerExtension: 'm3u8',
            season: 1,
            directSource: _hlsSintel,
          ),
        ],
      },
    ),
    7003: XtreamSeriesInfo(
      info: _seriesList[2],
      episodes: {
        1: [
          XtreamEpisode(
            id: 'demo_7003_s1e1',
            episodeNum: 1,
            title: 'Episode 3',
            containerExtension: 'm3u8',
            season: 1,
            directSource: _hlsTearsOfSteel,
          ),
        ],
      },
    ),
  };

  // ─── Public accessors (mirror XtreamApiService's shape) ─────────────────────

  static List<XtreamCategory> getLiveCategories() => List.of(_liveCategories);

  static List<XtreamLiveStream> getLiveStreams({String? categoryId}) {
    if (categoryId == null) return List.of(_liveStreams);
    return _liveStreams.where((s) => s.categoryId == categoryId).toList();
  }

  static List<XtreamCategory> getVodCategories() => List.of(_vodCategories);

  static List<XtreamVodStream> getVodStreams({String? categoryId}) {
    if (categoryId == null) return List.of(_vodStreams);
    return _vodStreams.where((s) => s.categoryId == categoryId).toList();
  }

  static XtreamVodInfo? getVodInfo(int vodId) {
    for (final movie in _vodStreams) {
      if (movie.streamId == vodId) {
        return XtreamVodInfo(movieData: movie, duration: '00:10:00');
      }
    }
    return null;
  }

  static List<XtreamCategory> getSeriesCategories() => List.of(_seriesCategories);

  static List<XtreamSeries> getSeriesList({String? categoryId}) {
    if (categoryId == null) return List.of(_seriesList);
    return _seriesList.where((s) => s.categoryId == categoryId).toList();
  }

  static XtreamSeriesInfo? getSeriesInfo(int seriesId) => _seriesInfoById[seriesId];
}
