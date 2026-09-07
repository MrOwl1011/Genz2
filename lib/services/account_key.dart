import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

/// Derives the opaque account identifier the sync backend knows a user by.
///
/// The same IPTV credentials produce the same key on every device, which is
/// what makes profiles, history and favorites follow a user around without
/// any pairing code. The backend only ever receives this hash — never the
/// username, the password, or the panel URL — so it cannot connect an
/// account to a particular streaming service.
///
/// ## This formula is frozen
///
/// Changing the salt, the iteration count, the digest, the separator or the
/// normalization below changes every user's key, which silently orphans
/// every existing account: their profiles and history stay in the database
/// attached to an id nothing computes any more. If it ever genuinely has to
/// change, it needs a versioned migration that derives both and merges, not
/// an edit to these constants.
///
/// ## Why PBKDF2 rather than a plain hash
///
/// The key is password-equivalent: it is stored server-side in plaintext as
/// the account's primary id, so a database leak hands an attacker the
/// hashes. IPTV credentials are typically short numeric strings, which a
/// bare SHA-256 would let them brute-force back to the original username and
/// password almost instantly. A deliberate work factor makes that
/// impractical. PBKDF2-HMAC-SHA256 is used rather than Argon2id purely
/// because `crypto` is already a dependency and this needs no new package;
/// at this iteration count it is a sound choice for the threat model.
class AccountKey {
  AccountKey._();

  /// Domain separation, so this hash can never collide with one derived for
  /// some other purpose from the same credentials.
  static const String _salt = 'genzplus.account-key.v1';

  /// ~0.3–0.6s on mobile hardware. Paid once per credential change, not per
  /// launch — callers are expected to cache the result (see AuthProvider).
  static const int _iterations = 120000;

  /// 32 bytes → 64 hex characters, matching `accounts.account_id CHAR(64)`
  /// exactly, so no schema change was needed to adopt this.
  static const int _keyLengthBytes = 32;

  /// Runs the derivation on a background isolate — 120k HMAC rounds would
  /// otherwise block the UI isolate for long enough to drop frames during
  /// login.
  static Future<String> derive({
    required String username,
    required String password,
  }) {
    return compute(_deriveSync, <String>[username, password]);
  }
}

/// Top-level so it can be handed to [compute].
String _deriveSync(List<String> credentials) {
  // Usernames are matched case-insensitively because panels and keyboards
  // both treat them that way. Passwords are NOT lowercased — they are
  // case-sensitive, and folding case would merge genuinely distinct
  // accounts and weaken the key.
  final username = credentials[0].trim().toLowerCase();
  final password = credentials[1].trim();

  // A NUL separator so ("ab", "c") and ("a", "bc") cannot derive the same
  // key — without it the concatenation is ambiguous.
  final secret = utf8.encode('$username\u0000$password');
  final salt = utf8.encode(AccountKey._salt);

  final key = _pbkdf2(
    secret: secret,
    salt: salt,
    iterations: AccountKey._iterations,
    lengthBytes: AccountKey._keyLengthBytes,
  );
  return key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// PBKDF2 as specified in RFC 8018, with HMAC-SHA256 as the PRF.
Uint8List _pbkdf2({
  required List<int> secret,
  required List<int> salt,
  required int iterations,
  required int lengthBytes,
}) {
  final hmac = Hmac(sha256, secret);
  final output = <int>[];

  for (var block = 1; output.length < lengthBytes; block++) {
    // U1 = PRF(secret, salt || INT_32_BE(block))
    var u = hmac
        .convert(<int>[
          ...salt,
          (block >> 24) & 0xFF,
          (block >> 16) & 0xFF,
          (block >> 8) & 0xFF,
          block & 0xFF,
        ])
        .bytes;
    final accumulated = List<int>.from(u);

    // T = U1 xor U2 xor ... xor Uc
    for (var round = 1; round < iterations; round++) {
      u = hmac.convert(u).bytes;
      for (var i = 0; i < accumulated.length; i++) {
        accumulated[i] ^= u[i];
      }
    }
    output.addAll(accumulated);
  }

  return Uint8List.fromList(output.sublist(0, lengthBytes));
}
