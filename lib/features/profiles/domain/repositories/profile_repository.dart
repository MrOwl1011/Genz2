import '../entities/profile_entity.dart';

/// Contract for profile CRUD — kept as a thin interface so ProfileProvider
/// depends on this, not directly on Hive/BackendApiService, per the clean-
/// architecture layering requested for the new profile/sync/devices feature
/// areas. (Deliberately no separate per-operation "usecase" classes on top of
/// this — for plain CRUD like this they'd just be a 1:1 forwarding wrapper
/// around a repository method, adding ceremony without real value; the rest
/// of this codebase's own convention is providers calling services directly.)
///
/// [token] is nullable everywhere on purpose: every write must succeed
/// locally first regardless of connectivity — a brand new or upgrading user
/// who happens to be offline on first launch still needs to be able to
/// create their default profile and have their existing favorites/history
/// migrate into it (see AuthProvider). When a token is available the same
/// call also pushes to the backend; when it isn't (or the push fails), the
/// write stays local-only until a later sync pass reconciles it (full queue-
/// based retry is a later phase — this just makes sure nothing is ever
/// *blocked* on connectivity).
abstract class ProfileRepository {
  /// Whatever's cached locally right now — safe to call with no network.
  List<ProfileEntity> getCachedProfiles(String accountId);

  /// Fetches the authoritative list from the backend and refreshes the local
  /// cache to match. Throws BackendApiException on failure — callers should
  /// fall back to getCachedProfiles() in that case.
  Future<List<ProfileEntity>> refreshProfiles(String accountId, String token);

  Future<ProfileEntity> createProfile(
    String accountId,
    String? token, {
    required String name,
    required String avatar,
    required bool isKids,
  });

  Future<ProfileEntity> updateProfile(
    String accountId,
    String? token, {
    required String profileId,
    String? name,
    String? avatar,
    bool? isKids,
  });

  Future<void> deleteProfile(String accountId, String? token, String profileId);
}
