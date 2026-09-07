import '../../../../core/hive/hive_boxes.dart';
import '../../domain/entities/sync_mutation.dart';

/// One Hive-backed outbox for every profile's pending offline writes —
/// entries are auto-keyed (box.add()) and read back in insertion (FIFO)
/// order via toMap(), which Hive preserves.
class SyncQueueLocalDataSource {
  List<MapEntry<dynamic, SyncMutation>> getAll() {
    return HiveBoxes.syncQueueBox
        .toMap()
        .entries
        .where((e) => e.value is String)
        .map(
          (e) =>
              MapEntry(e.key, SyncMutation.fromJsonString(e.value as String)),
        )
        .toList();
  }

  /// Adds [mutation], or — if an unflushed entry already exists for the same
  /// coalesceKey (same row) — overwrites that entry in place instead of
  /// appending a second one. See SyncMutation.coalesceKey.
  Future<void> enqueue(SyncMutation mutation) async {
    final box = HiveBoxes.syncQueueBox;
    dynamic matchKey;
    for (final entry in box.toMap().entries) {
      if (entry.value is! String) continue;
      final existing = SyncMutation.fromJsonString(entry.value as String);
      if (existing.coalesceKey == mutation.coalesceKey) {
        matchKey = entry.key;
        break;
      }
    }

    if (matchKey != null) {
      await box.put(matchKey, mutation.toJsonString());
    } else {
      await box.add(mutation.toJsonString());
    }
  }

  Future<void> remove(dynamic key) async {
    await HiveBoxes.syncQueueBox.delete(key);
  }
}
