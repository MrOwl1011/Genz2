import '../models/xtream_models.dart';
import 'xtream_api_service.dart';

/// Fully local mock backend used for App Store / Play Store review.
///
/// Reviewers are given the credentials below (server `kDemoServerUrl` +
/// either demo account) instead of a real IPTV subscription. When those
/// exact credentials are used, [AuthProvider] and [ContentProvider] both
/// detect it via [DemoDataService.isDemoLogin] and serve everything from
/// here instead of ever making a network call to `kDemoServerUrl` (which
/// isn't a real server) — categories, listings and metadata are all static
/// in-memory data, and playback uses public, freely licensed HLS/MP4 test
/// streams so the player itself can still be exercised end to end.
class DemoDataService {
  DemoDataService._();

  /// The server address demo accounts must be entered with. Not a real
  /// server — matching against this is what flags a login as demo mode.
  static const String kDemoServerUrl = 'https://demo.genzplus.app';

  static const Map<String, String> _demoAccounts = {
    'demo': 'demo123',
    'test': 'test123',
  };

  /// True if [serverUrl]/[username]/[password] exactly match one of the two
  /// published demo accounts. Used to gate demo mode everywhere it matters.
  ///
  /// Compares hostname only (ignoring scheme/trailing slash) so reviewers
  /// still land in demo mode even if they type the server without
  /// "https://" or with different casing.
  static bool isDemoLogin(String serverUrl, String username, String password) {
    final normalizedBase = XtreamApiService.getBaseUrl(
      XtreamApiService.normalizeUrl(serverUrl),
    );
    final host = Uri.tryParse(normalizedBase)?.host.toLowerCase() ?? '';
    final demoHost = Uri.parse(kDemoServerUrl).host.toLowerCase();
    if (host.isEmpty || host != demoHost) return false;
    return _demoAccounts[username.trim()] == password.trim();
  }

  static XtreamUser buildDemoUser(String username) {
    return XtreamUser(
      username: username,
      status: 'Demo Mode',
      expiryDate: null, // shown as "Lifetime / Unlimited" in the UI
      maxConnections: 1,
      activeConnections: 0,
      allowedOutputs: const ['m3u8', 'ts', 'mp4'],
    );
  }

  // ─── Public-domain / official test streams ─────────────────────────────────
  // HLS (for Live TV):
  static const _hlsBipBop =
      'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8';
  static const _hlsAdvanced =
      'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8';
  static const _hlsMux = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

  // Progressive MP4 (for Movies/Series) — Google's publicly hosted sample
  // clips (Creative-Commons Blender Foundation shorts + Google demo assets).
  static const _mp4Base = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample';
  static const _mp4BigBuckBunny = '$_mp4Base/BigBuckBunny.mp4';
  static const _mp4ElephantsDream = '$_mp4Base/ElephantsDream.mp4';
  static const _mp4Sintel = '$_mp4Base/Sintel.mp4';
  static const _mp4TearsOfSteel = '$_mp4Base/TearsOfSteel.mp4';
  static const _mp4ForBiggerBlazes = '$_mp4Base/ForBiggerBlazes.mp4';
  static const _mp4ForBiggerEscapes = '$_mp4Base/ForBiggerEscapes.mp4';
  static const _mp4ForBiggerFun = '$_mp4Base/ForBiggerFun.mp4';
  static const _mp4ForBiggerJoyrides = '$_mp4Base/ForBiggerJoyrides.mp4';
  static const _mp4ForBiggerMeltdowns = '$_mp4Base/ForBiggerMeltdowns.mp4';

  // ─── Live TV ─────────────────────────────────────────────────────────────

  static final List<XtreamCategory> _liveCategories = [
    XtreamCategory(categoryId: 'demo_live_news', categoryName: 'News', parentId: 0),
    XtreamCategory(categoryId: 'demo_live_sports', categoryName: 'Sports', parentId: 0),
    XtreamCategory(categoryId: 'demo_live_entertainment', categoryName: 'Entertainment', parentId: 0),
  ];

  static final List<XtreamLiveStream> _liveStreams = [
    XtreamLiveStream(
      streamId: 9001,
      name: 'Demo News 24/7',
      streamIcon: '',
      categoryId: 'demo_live_news',
      num: 1,
      directSource: _hlsBipBop,
    ),
    XtreamLiveStream(
      streamId: 9002,
      name: 'Demo World News',
      streamIcon: '',
      categoryId: 'demo_live_news',
      num: 2,
      directSource: _hlsAdvanced,
    ),
    XtreamLiveStream(
      streamId: 9003,
      name: 'Demo Sports HD',
      streamIcon: '',
      categoryId: 'demo_live_sports',
      num: 3,
      directSource: _hlsMux,
    ),
    XtreamLiveStream(
      streamId: 9004,
      name: 'Demo Sports Extra',
      streamIcon: '',
      categoryId: 'demo_live_sports',
      num: 4,
      directSource: _hlsBipBop,
    ),
    XtreamLiveStream(
      streamId: 9005,
      name: 'Demo Entertainment',
      streamIcon: '',
      categoryId: 'demo_live_entertainment',
      num: 5,
      directSource: _hlsAdvanced,
    ),
    XtreamLiveStream(
      streamId: 9006,
      name: 'Demo Music Channel',
      streamIcon: '',
      categoryId: 'demo_live_entertainment',
      num: 6,
      directSource: _hlsMux,
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
      containerExtension: 'mp4',
      plot: 'A sample demo movie used to preview playback in GenZ+.',
      genre: 'Animation',
      releaseDate: '2008-04-10',
      rating: '4.5',
      added: '1700000000',
      directSource: _mp4BigBuckBunny,
    ),
    XtreamVodStream(
      streamId: 8002,
      name: 'For Bigger Blazes',
      streamIcon: '',
      categoryId: 'demo_vod_action',
      containerExtension: 'mp4',
      plot: 'A sample demo clip used to preview playback in GenZ+.',
      genre: 'Action',
      releaseDate: '2014-01-01',
      rating: '4.0',
      added: '1700000100',
      directSource: _mp4ForBiggerBlazes,
    ),
    XtreamVodStream(
      streamId: 8003,
      name: 'For Bigger Escapes',
      streamIcon: '',
      categoryId: 'demo_vod_action',
      containerExtension: 'mp4',
      plot: 'A sample demo clip used to preview playback in GenZ+.',
      genre: 'Action',
      releaseDate: '2014-01-02',
      rating: '3.9',
      added: '1700000200',
      directSource: _mp4ForBiggerEscapes,
    ),
    XtreamVodStream(
      streamId: 8004,
      name: 'For Bigger Fun',
      streamIcon: '',
      categoryId: 'demo_vod_comedy',
      containerExtension: 'mp4',
      plot: 'A sample demo clip used to preview playback in GenZ+.',
      genre: 'Comedy',
      releaseDate: '2014-01-03',
      rating: '4.2',
      added: '1700000300',
      directSource: _mp4ForBiggerFun,
    ),
    XtreamVodStream(
      streamId: 8005,
      name: 'For Bigger Joyrides',
      streamIcon: '',
      categoryId: 'demo_vod_comedy',
      containerExtension: 'mp4',
      plot: 'A sample demo clip used to preview playback in GenZ+.',
      genre: 'Comedy',
      releaseDate: '2014-01-04',
      rating: '4.1',
      added: '1700000400',
      directSource: _mp4ForBiggerJoyrides,
    ),
    XtreamVodStream(
      streamId: 8006,
      name: 'For Bigger Meltdowns',
      streamIcon: '',
      categoryId: 'demo_vod_comedy',
      containerExtension: 'mp4',
      plot: 'A sample demo clip used to preview playback in GenZ+.',
      genre: 'Comedy',
      releaseDate: '2014-01-05',
      rating: '3.8',
      added: '1700000500',
      directSource: _mp4ForBiggerMeltdowns,
    ),
    XtreamVodStream(
      streamId: 8007,
      name: 'Elephants Dream',
      streamIcon: '',
      categoryId: 'demo_vod_drama',
      containerExtension: 'mp4',
      plot: 'A sample demo movie used to preview playback in GenZ+.',
      genre: 'Drama',
      releaseDate: '2006-03-24',
      rating: '4.3',
      added: '1700000600',
      directSource: _mp4ElephantsDream,
    ),
    XtreamVodStream(
      streamId: 8008,
      name: 'Sintel',
      streamIcon: '',
      categoryId: 'demo_vod_drama',
      containerExtension: 'mp4',
      plot: 'A sample demo movie used to preview playback in GenZ+.',
      genre: 'Drama',
      releaseDate: '2010-09-30',
      rating: '4.7',
      added: '1700000700',
      directSource: _mp4Sintel,
    ),
    XtreamVodStream(
      streamId: 8009,
      name: 'Tears of Steel',
      streamIcon: '',
      categoryId: 'demo_vod_drama',
      containerExtension: 'mp4',
      plot: 'A sample demo movie used to preview playback in GenZ+.',
      genre: 'Sci-Fi',
      releaseDate: '2012-09-26',
      rating: '4.4',
      added: '1700000800',
      directSource: _mp4TearsOfSteel,
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
            containerExtension: 'mp4',
            season: 1,
            directSource: _mp4BigBuckBunny,
          ),
          XtreamEpisode(
            id: 'demo_7001_s1e2',
            episodeNum: 2,
            title: 'Episode 2',
            containerExtension: 'mp4',
            season: 1,
            directSource: _mp4ForBiggerFun,
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
            title: 'Episode 1',
            containerExtension: 'mp4',
            season: 1,
            directSource: _mp4ForBiggerJoyrides,
          ),
          XtreamEpisode(
            id: 'demo_7002_s1e2',
            episodeNum: 2,
            title: 'Episode 2',
            containerExtension: 'mp4',
            season: 1,
            directSource: _mp4ForBiggerMeltdowns,
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
            title: 'Episode 1',
            containerExtension: 'mp4',
            season: 1,
            directSource: _mp4ElephantsDream,
          ),
        ],
        2: [
          XtreamEpisode(
            id: 'demo_7003_s2e1',
            episodeNum: 1,
            title: 'Episode 1',
            containerExtension: 'mp4',
            season: 2,
            directSource: _mp4TearsOfSteel,
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
