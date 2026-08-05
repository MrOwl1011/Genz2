/// A Netflix-style viewer profile under one Xtream account. Pure domain
/// object — no JSON, no storage concerns (see data/models/profile_model.dart
/// for that).
class ProfileEntity {
  final String profileId;
  final String name;
  final String avatar;
  final bool isKids;
  final DateTime updatedAt;

  const ProfileEntity({
    required this.profileId,
    required this.name,
    required this.avatar,
    required this.isKids,
    required this.updatedAt,
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
    );
  }
}
