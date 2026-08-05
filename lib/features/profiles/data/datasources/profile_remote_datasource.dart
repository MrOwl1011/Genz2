import '../../../../services/backend_api_service.dart';
import '../models/profile_model.dart';

class ProfileRemoteDataSource {
  final BackendApiService _api;

  ProfileRemoteDataSource([BackendApiService? api]) : _api = api ?? BackendApiService();

  Future<List<ProfileModel>> list(String token) async {
    final rows = await _api.listProfiles(token);
    return rows.map(ProfileModel.fromBackendJson).toList();
  }

  Future<ProfileModel> create(String token, ProfileModel profile) async {
    final row = await _api.createProfile(
      token,
      profileId: profile.profileId,
      name: profile.name,
      avatar: profile.avatar,
      isKids: profile.isKids,
      updatedAt: profile.updatedAt,
    );
    return ProfileModel.fromBackendJson(row);
  }

  Future<ProfileModel> update(String token, ProfileModel profile) async {
    final row = await _api.updateProfile(
      token,
      profileId: profile.profileId,
      name: profile.name,
      avatar: profile.avatar,
      isKids: profile.isKids,
      updatedAt: profile.updatedAt,
    );
    return ProfileModel.fromBackendJson(row);
  }

  Future<void> delete(String token, String profileId) async {
    await _api.deleteProfile(token, profileId);
  }
}
