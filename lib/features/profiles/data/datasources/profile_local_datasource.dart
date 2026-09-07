import '../../../../core/hive/hive_boxes.dart';
import '../models/profile_model.dart';

/// Reads/writes the whole profile list for one account as a single Hive
/// entry — see HiveBoxes.profilesBox doc comment for why (matches the
/// existing single-blob-per-scope convention used by favorites/history
/// elsewhere in this app, and trivially preserves display order without
/// needing a separate sort key, since the list is always written back
/// exactly as the caller ordered it).
class ProfileLocalDataSource {
  List<ProfileModel> getAll(String accountId) {
    final raw = HiveBoxes.profilesBox.get(accountId);
    if (raw == null) return [];
    final list = (raw['profiles'] as List?) ?? const [];
    return list
        .map(
          (e) => ProfileModel.fromHiveMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<void> saveAll(String accountId, List<ProfileModel> profiles) async {
    await HiveBoxes.profilesBox.put(accountId, {
      'profiles': profiles.map((p) => p.toHiveMap()).toList(),
    });
  }
}
