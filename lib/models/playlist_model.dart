/// Model representing a saved Xtream playlist/account.
library;

import 'dart:convert';

class Playlist {
  final String id;
  final String playlistName;
  final String username;
  final String password;
  final String serverUrl;
  final DateTime? lastLogin;
  final DateTime? createdAt;

  Playlist({
    required this.id,
    required this.playlistName,
    required this.username,
    required this.password,
    required this.serverUrl,
    this.lastLogin,
    this.createdAt,
  });

  /// Same formula as AuthProvider.playlistId — must always match so that
  /// favorites/history keyed by this id stay in sync with the active session.
  static String computeId(String serverUrl, String username) {
    return base64Encode(utf8.encode('${serverUrl}_$username'));
  }

  /// Fixed-length mask so the real password length is never leaked in the UI.
  String get maskedPassword => '•' * 8;

  factory Playlist.fromMap(Map<String, String> map) {
    final url = map['url'] ?? '';
    final username = map['username'] ?? '';
    return Playlist(
      id: computeId(url, username),
      playlistName: map['name'] ?? 'My Playlist',
      username: username,
      password: map['password'] ?? '',
      serverUrl: url,
      lastLogin: map['lastLogin'] != null ? DateTime.tryParse(map['lastLogin']!) : null,
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt']!) : null,
    );
  }

  Map<String, String> toMap() {
    return {
      'name': playlistName,
      'url': serverUrl,
      'username': username,
      'password': password,
      if (lastLogin != null) 'lastLogin': lastLogin!.toIso8601String(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}
