import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Central place for Hive initialization + box handles for the profile/sync
/// feature area. Deliberately not using generated TypeAdapters — every model
/// in this feature area hand-writes toJson()/fromJson() (matching the
/// convention FavoriteItem/HistoryItem/DownloadItem already use elsewhere in
/// this codebase) and is stored as a plain Map, so there's no build_runner
/// step to keep in sync.
class HiveBoxes {
  HiveBoxes._();

  static const String meta = 'meta_box';
  static const String profiles = 'profiles_box';
  static const String favorites = 'favorites_box';
  static const String history = 'history_box';
  static const String syncQueue = 'sync_queue_box';

  /// Call once, before runApp(), same as the rest of main.dart's startup
  /// sequence.
  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox(meta),
      Hive.openBox<Map>(profiles),
      Hive.openBox(favorites),
      Hive.openBox(history),
      Hive.openBox(syncQueue),
    ]);
  }

  /// Mixed-type box for small standalone values (currently just device_id).
  static Box get metaBox => Hive.box(meta);

  /// Key = accountId; value = `{'profiles': [profileMap, ...]}` — one entry
  /// per account holding its whole (small, max-5) profile list as an
  /// ordered array. Profile records are flat (a handful of string/bool
  /// fields, no arbitrary nested content), so raw Map storage is fine here —
  /// contrast with favoritesBox/historyBox below.
  static Box<Map> get profilesBox => Hive.box<Map>(profiles);

  /// Key = `'${accountId}__${profileId}'`; value = a **JSON-encoded string**
  /// (via jsonEncode/jsonDecode), not a raw Hive Map — deliberately, since
  /// favorite/history items embed `rawData`: an arbitrary, deeply-nested
  /// Map straight from the Xtream API's JSON response, whose exact shape
  /// isn't fully controlled. Storing that as a native Hive Map hit real
  /// silent write failures in practice (visible in-memory, gone after an
  /// app restart) — encoding to a plain String first sidesteps Hive's
  /// nested-type handling entirely and reuses the exact same json codec the
  /// legacy SharedPreferences-backed storage already relied on successfully.
  static Box get favoritesBox => Hive.box(favorites);

  /// Same key shape and JSON-string storage as favoritesBox, same reason.
  /// Deliberately does NOT include episode_id in the key, matching how the
  /// existing HistoryItem.id is already the sole dedup key server-side and
  /// client-side today.
  static Box get historyBox => Hive.box(history);

  /// Outbox/mutation log for offline sync — auto-incrementing int keys via
  /// box.add(), FIFO by key order. Also JSON-string-encoded per entry, same
  /// reasoning as favoritesBox (a queued mutation's payload can itself embed
  /// the same arbitrary rawData).
  static Box get syncQueueBox => Hive.box(syncQueue);
}
