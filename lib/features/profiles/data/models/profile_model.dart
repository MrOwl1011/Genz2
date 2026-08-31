import '../../../../core/datetime_utils.dart';
import '../../domain/entities/profile_entity.dart';

/// Adds JSON (backend + Hive) serialization on top of [ProfileEntity].
/// Hand-written, no code generation — matches how FavoriteItem/HistoryItem/
/// DownloadItem already serialize themselves elsewhere in this codebase.
class ProfileModel extends ProfileEntity {
  const ProfileModel({
    required super.profileId,
    required super.name,
    required super.avatar,
    required super.isKids,
    required super.updatedAt,
    super.favoritesClearedAt,
    super.historyClearedAt,
  });

  factory ProfileModel.fromEntity(ProfileEntity entity) {
    return ProfileModel(
      profileId: entity.profileId,
      name: entity.name,
      avatar: entity.avatar,
      isKids: entity.isKids,
      updatedAt: entity.updatedAt,
      favoritesClearedAt: entity.favoritesClearedAt,
      historyClearedAt: entity.historyClearedAt,
    );
  }

  static DateTime? _parseBackendUtcOrNull(dynamic value) {
    if (value == null) return null;
    return parseBackendUtc(value as String);
  }

  /// From a backend API response (`profile_id`/`is_kids` snake_case,
  /// `updated_at` a UTC-no-marker string — see parseBackendUtc).
  factory ProfileModel.fromBackendJson(Map<String, dynamic> json) {
    return ProfileModel(
      profileId: json['profile_id'] as String,
      name: json['name'] as String,
      avatar: (json['avatar'] as String?) ?? 'default',
      isKids: json['is_kids'] == true,
      updatedAt: parseBackendUtc(json['updated_at'] as String),
      favoritesClearedAt: _parseBackendUtcOrNull(json['favorites_cleared_at']),
      historyClearedAt: _parseBackendUtcOrNull(json['history_cleared_at']),
    );
  }

  /// From this app's own local Hive storage (see profile_local_datasource.dart)
  /// — a plain Map this same model wrote via toHiveMap(), so updatedAt is a
  /// normal ISO-8601 string with a timezone marker already (unlike the
  /// backend's marker-less format).
  factory ProfileModel.fromHiveMap(Map map) {
    return ProfileModel(
      profileId: map['profileId'] as String,
      name: map['name'] as String,
      avatar: map['avatar'] as String,
      isKids: map['isKids'] as bool,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      favoritesClearedAt: map['favoritesClearedAt'] != null
          ? DateTime.parse(map['favoritesClearedAt'] as String)
          : null,
      historyClearedAt: map['historyClearedAt'] != null
          ? DateTime.parse(map['historyClearedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toHiveMap() {
    return {
      'profileId': profileId,
      'name': name,
      'avatar': avatar,
      'isKids': isKids,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'favoritesClearedAt': favoritesClearedAt?.toUtc().toIso8601String(),
      'historyClearedAt': historyClearedAt?.toUtc().toIso8601String(),
    };
  }
}
