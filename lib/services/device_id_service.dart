import '../core/hive/hive_boxes.dart';
import '../core/uuid.dart';

/// Persists a stable per-install device identifier — generated once, reused
/// for the lifetime of the app install. Sent with every backend login/sync
/// call so the backend can tell devices apart under one account (see
/// backend/README.md's `devices` table).
class DeviceIdService {
  DeviceIdService._();

  static const String _key = 'device_id';

  static String getOrCreate() {
    final box = HiveBoxes.metaBox;
    final existing = box.get(_key);
    if (existing is String && existing.isNotEmpty) {
      return existing;
    }

    final generated = generateUuidV4();
    box.put(_key, generated);
    return generated;
  }
}
