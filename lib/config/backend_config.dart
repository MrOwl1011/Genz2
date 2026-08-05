/// App-level configuration for the profile/sync backend (see backend/
/// at the repo root). Unlike server_url/username (per-user Xtream
/// credentials), these two values are the same for every install of this
/// app — they describe *this app's* backend, not the end user's IPTV
/// provider.
class BackendConfig {
  BackendConfig._();

  /// No trailing slash. Matches wherever backend/ was deployed — see
  /// backend/README.md.
  static const String baseUrl = 'https://api.shitaa.online';

  /// Must exactly match API_KEY in backend/config.php on the server.
  static const String apiKey = 'hakonamatata';
}
