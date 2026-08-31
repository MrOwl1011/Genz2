import 'package:flutter/material.dart';

import '../../../../core/hive/hive_boxes.dart';
import '../../../../providers/user_prefs_provider.dart';
import '../../../../services/backend_api_service.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

/// Netflix-style "who's watching" state: the profile list for the currently
/// logged-in account, and which one is active. A distinct concern from
/// AuthProvider (Xtream login) and UserPrefsProvider (favorites/history
/// storage) — this owns none of that, it only owns the profile picker.
///
/// Takes [userPrefs] directly (same constructor-injection pattern
/// AuthProvider already uses for its own sibling providers) so that
/// selecting a profile can immediately re-scope favorites/history storage
/// via UserPrefsProvider.setProfileScope — no extra plumbing needed in
/// main.dart beyond passing the same instance to both.
class ProfileProvider extends ChangeNotifier {
  final UserPrefsProvider userPrefs;
  final ProfileRepository _repository;

  ProfileProvider(this.userPrefs, {ProfileRepository? repository})
    : _repository = repository ?? ProfileRepositoryImpl();

  String? _accountId;
  String? _deviceToken;
  List<ProfileEntity> _profiles = [];
  ProfileEntity? _activeProfile;
  bool _isLoading = false;
  String? _errorMessage;

  List<ProfileEntity> get profiles => _profiles;
  ProfileEntity? get activeProfile => _activeProfile;
  bool get hasActiveProfile => _activeProfile != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get canCreateMore => _profiles.length < 5;

  /// Called right after AuthProvider finishes logging in (whether the
  /// backend login succeeded or not — see AuthProvider._connectBackendAndProfiles).
  /// [deviceToken] is null when the backend couldn't be reached; the picker
  /// still works in that case, just showing whatever was cached locally last
  /// time it *did* reach the backend (or nothing yet, for a brand new
  /// install — AuthProvider handles creating a default profile either way).
  Future<void> loadForAccount(String accountId, String? deviceToken) async {
    _accountId = accountId;
    _deviceToken = deviceToken;
    _activeProfile = null;
    _errorMessage = null;

    _profiles = _repository.getCachedProfiles(accountId);
    notifyListeners();

    if (deviceToken == null) {
      return; // offline — stick with the cached list above
    }

    _isLoading = true;
    notifyListeners();
    try {
      _profiles = await _repository.refreshProfiles(accountId, deviceToken);
    } on BackendApiException catch (e) {
      // Non-fatal: keep showing the cached list from above, just surface why
      // it might be stale.
      _errorMessage = e.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _lastProfileKey(String accountId) => 'last_profile_$accountId';

  void selectProfile(ProfileEntity profile) {
    _activeProfile = profile;
    final accountId = _accountId;
    if (accountId != null) {
      userPrefs.setProfileScope(
        accountId,
        profile.profileId,
        deviceToken: _deviceToken,
        favoritesClearedAt: profile.favoritesClearedAt,
        historyClearedAt: profile.historyClearedAt,
      );
      // Persisted so the *next* app launch can skip the picker and resume
      // straight into this same profile — see tryRestoreLastProfile(),
      // called from AuthProvider right after loadForAccount(). Without this,
      // every cold start forgot which profile was active (a plain in-memory
      // field, reset on every fresh process) and silently landed on
      // legacy/unscoped storage until the user manually re-picked — easy to
      // mistake for "my favorites/history disappeared" when they're actually
      // still there, just not loaded yet.
      HiveBoxes.metaBox.put(_lastProfileKey(accountId), profile.profileId);
    }
    notifyListeners();
  }

  /// Called once right after loadForAccount() populates the profile list —
  /// if this account was last left on a still-existing profile, resume it
  /// automatically instead of making the user pick again on every app
  /// launch. Returns true if it auto-selected something.
  bool tryRestoreLastProfile() {
    final accountId = _accountId;
    if (accountId == null || hasActiveProfile) return false;

    final lastId = HiveBoxes.metaBox.get(_lastProfileKey(accountId));
    if (lastId is! String) return false;

    for (final profile in _profiles) {
      if (profile.profileId == lastId) {
        selectProfile(profile);
        return true;
      }
    }
    return false; // that profile was deleted/renamed away since — let the picker show
  }

  void clearActiveProfile() {
    _activeProfile = null;
    notifyListeners();
  }

  Future<bool> createProfile({
    required String name,
    required String avatar,
    bool isKids = false,
  }) async {
    final accountId = _accountId;
    if (accountId == null) return false;
    if (!canCreateMore) {
      _errorMessage = 'Maximum of 5 profiles reached.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final created = await _repository.createProfile(
        accountId,
        _deviceToken,
        name: name,
        avatar: avatar,
        isKids: isKids,
      );
      _profiles = [..._profiles, created];
      return true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile(
    String profileId, {
    String? name,
    String? avatar,
    bool? isKids,
  }) async {
    final accountId = _accountId;
    if (accountId == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _repository.updateProfile(
        accountId,
        _deviceToken,
        profileId: profileId,
        name: name,
        avatar: avatar,
        isKids: isKids,
      );
      _profiles = [
        for (final p in _profiles)
          if (p.profileId == profileId) updated else p,
      ];
      if (_activeProfile?.profileId == profileId) {
        _activeProfile = updated;
      }
      return true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteProfile(String profileId) async {
    final accountId = _accountId;
    if (accountId == null) return false;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.deleteProfile(accountId, _deviceToken, profileId);
      _profiles = _profiles.where((p) => p.profileId != profileId).toList();
      if (_activeProfile?.profileId == profileId) {
        _activeProfile = null;
      }
      return true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Called from AuthProvider.logout().
  void reset() {
    _accountId = null;
    _deviceToken = null;
    _profiles = [];
    _activeProfile = null;
    _errorMessage = null;
    notifyListeners();
  }
}
