import '../core/hive/hive_boxes.dart';
import '../core/uuid.dart';

/// Persists a stable per-install device identifier — generated once, reused
/// for the lifetime of the app install. Sent with every backend login/sync
/// call so the backend can tell devices apart under one account (see
/// backend/README.md's `devices` table).
class DeviceIdService {
  DeviceIdService._();

  static const String _key = 'device_id';

  /// Falls back to a fresh, unpersisted id on any storage failure rather
  /// than throwing — this runs inline inside AuthProvider's backend-login
  /// call, and an uncaught exception here (a corrupt/inaccessible Hive box,
  /// seen in practice on some real device storage that behaves less
  /// predictably than an emulator's) would silently abort that entire
  /// call before it even reaches the network, which looked identical to
  /// "can't connect to the backend" with no error to explain why. A
  /// same-session-only id is still enough for that one login attempt to
  /// succeed; it just won't survive a restart.
  static String getOrCreate() {
    try {
      final box = HiveBoxes.metaBox;
      final existing = box.get(_key);
      if (existing is String && existing.isNotEmpty) {
        return existing;
      }

      final generated = generateUuidV4();
      box.put(_key, generated);
      return generated;
    } catch (_) {
      return generateUuidV4();
    }
  }
}
