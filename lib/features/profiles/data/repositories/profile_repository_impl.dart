import '../../../../core/uuid.dart';
import '../../../../services/backend_api_service.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_local_datasource.dart';
import '../datasources/profile_remote_datasource.dart';
import '../models/profile_model.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final ProfileLocalDataSource _local;
  final ProfileRemoteDataSource _remote;

  ProfileRepositoryImpl({
    ProfileLocalDataSource? local,
    ProfileRemoteDataSource? remote,
  }) : _local = local ?? ProfileLocalDataSource(),
       _remote = remote ?? ProfileRemoteDataSource();

  @override
  List<ProfileEntity> getCachedProfiles(String accountId) =>
      _local.getAll(accountId);

  @override
  Future<List<ProfileEntity>> refreshProfiles(
    String accountId,
    String token,
  ) async {
    final remote = await _remote.list(token);
    await _local.saveAll(accountId, remote);
    return remote;
  }

  @override
  Future<ProfileEntity> createProfile(
    String accountId,
    String? token, {
    required String name,
    required String avatar,
    required bool isKids,
  }) async {
    final draft = ProfileModel(
      profileId: generateUuidV4(),
      name: name,
      avatar: avatar,
      isKids: isKids,
      updatedAt: DateTime.now().toUtc(),
    );

    // Always write locally first — must succeed with no network at all, see
    // ProfileRepository's doc comment.
    final current = _local.getAll(accountId);
    await _local.saveAll(accountId, [...current, draft]);

    if (token == null) return draft;

    try {
      final created = await _remote.create(token, draft);
      await _replaceLocal(accountId, draft.profileId, created);
      return created;
    } on BackendApiException {
      return draft; // stays local-only; reconciled by a later sync pass
    }
  }

  @override
  Future<ProfileEntity> updateProfile(
    String accountId,
    String? token, {
    required String profileId,
    String? name,
    String? avatar,
    bool? isKids,
  }) async {
    final current = _local.getAll(accountId);
    final existing = current.firstWhere((p) => p.profileId == profileId);

    final draft = ProfileModel(
      profileId: profileId,
      name: name ?? existing.name,
      avatar: avatar ?? existing.avatar,
      isKids: isKids ?? existing.isKids,
      updatedAt: DateTime.now().toUtc(),
    );
    await _replaceLocal(accountId, profileId, draft);

    if (token == null) return draft;

    try {
      final updated = await _remote.update(token, draft);
      await _replaceLocal(accountId, profileId, updated);
      return updated;
    } on BackendApiException {
      return draft; // stays local-only; reconciled by a later sync pass
    }
  }

  @override
  Future<void> deleteProfile(
    String accountId,
    String? token,
    String profileId,
  ) async {
    final current = _local.getAll(accountId);
    await _local.saveAll(
      accountId,
      current.where((p) => p.profileId != profileId).toList(),
    );

    if (token == null) return;

    try {
      await _remote.delete(token, profileId);
    } on BackendApiException {
      // Deleted locally already; a later sync pass (once the queue exists)
      // will need to replay this against the backend too.
    }
  }

  Future<void> _replaceLocal(
    String accountId,
    String profileId,
    ProfileModel replacement,
  ) async {
    final current = _local.getAll(accountId);
    await _local.saveAll(accountId, [
      for (final p in current)
        if (p.profileId == profileId) replacement else p,
    ]);
  }
}
