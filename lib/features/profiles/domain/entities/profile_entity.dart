/// A Netflix-style viewer profile under one Xtream account. Pure domain
/// object — no JSON, no storage concerns (see data/models/profile_model.dart
/// for that).
class ProfileEntity {
  final String profileId;
  final String name;
  final String avatar;
  final bool isKids;
  final DateTime updatedAt;

  /// Set server-side only by the admin panel's "Clear Favorites"/"Clear
  /// History" actions — never by the app. UserPrefsProvider.setProfileScope
  /// compares these against a locally stored "last applied" marker and
  /// wipes local favorites/history for this profile when newer, since the
  /// normal sync merge only ever adds items and would otherwise never
  /// reflect an admin-initiated clear.
  final DateTime? favoritesClearedAt;
  final DateTime? historyClearedAt;

  const ProfileEntity({
    required this.profileId,
    required this.name,
    required this.avatar,
    required this.isKids,
    required this.updatedAt,
    this.favoritesClearedAt,
    this.historyClearedAt,
  });

  ProfileEntity copyWith({
    String? name,
    String? avatar,
    bool? isKids,
    DateTime? updatedAt,
  }) {
    return ProfileEntity(
      profileId: profileId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      isKids: isKids ?? this.isKids,
      updatedAt: updatedAt ?? this.updatedAt,
      favoritesClearedAt: favoritesClearedAt,
      historyClearedAt: historyClearedAt,
    );
  }
}
