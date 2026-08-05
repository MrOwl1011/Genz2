import 'dart:convert';
import 'package:crypto/crypto.dart';

/// account_id = SHA256(normalize(server_url) + normalize(username)).
///
/// CRITICAL: must stay byte-for-byte identical to
/// backend/lib/account_id.php's compute_account_id() — see that file's doc
/// comment for why (drifting the two formulas apart means the same Xtream
/// account computes a different id on the client vs. the server and
/// silently fails to match up).
///
/// normalize = lowercase + trim + strip a single trailing slash. Deliberately
/// separate from AuthProvider.playlistId's existing base64(serverUrl_username)
/// formula — that one is unnormalized and pre-dates this feature; both stay
/// in use for their own separate purposes (see AuthProvider).
String normalizeServerUrl(String serverUrl) {
  var normalized = serverUrl.trim().toLowerCase();
  if (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

String normalizeUsername(String username) => username.trim().toLowerCase();

String computeAccountId(String serverUrl, String username) {
  final input = normalizeServerUrl(serverUrl) + normalizeUsername(username);
  return sha256.convert(utf8.encode(input)).toString();
}
