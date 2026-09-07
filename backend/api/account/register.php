<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/account_id.php';
require_once __DIR__ . '/../../lib/pairing.php';
require_once __DIR__ . '/../../lib/db.php';

/**
 * Replaces login.php as the only way to obtain a device token. The
 * difference is exactly one thing: this never sees an Xtream server URL,
 * username or password, and never makes an outbound call to any IPTV
 * panel — it hands out an account_id nobody, including this server, can
 * connect to a particular streaming service. See account_id.php's
 * generate_anonymous_account_id() doc comment and backend/README.md for the
 * full reasoning (this exists specifically to answer an App Store Guideline
 * 5.6 rejection).
 *
 * Two ways this can be called:
 *   - No pairing_code: mints a brand-new, empty anonymous account. This is
 *     what a fresh install does automatically, with no user action.
 *   - pairing_code from generate_pairing_code() (see pairing.php): joins the
 *     account that code was issued for instead of creating a new one, so a
 *     second device sees the first device's profiles/favorites/history.
 *     An invalid/expired code is not an error — it silently falls back to
 *     creating a new account, since a user who mistyped a code should still
 *     end up with a working (if unlinked) app rather than a hard failure.
 */
require_api_key();

$body = read_json_body();

$deviceId = isset($body['device_id']) ? (string) $body['device_id'] : '';
$deviceName = isset($body['device_name']) ? (string) $body['device_name'] : '';
$platform = isset($body['platform']) ? (string) $body['platform'] : '';
$pairingCode = isset($body['pairing_code']) ? trim((string) $body['pairing_code']) : '';
// Derived on the device from the user's own IPTV credentials — see
// lib/services/account_key.dart. It reaches us already hashed, so this
// server never sees the username, the password or the panel URL and
// cannot connect an account to a streaming service. Optional: an install
// that hasn't logged into a panel yet still gets an anonymous account, as
// before.
$accountKey = isset($body['account_key']) ? strtolower(trim((string) $body['account_key'])) : '';

if ($deviceId === '' || $deviceName === '' || $platform === '') {
    json_error('INVALID_BODY', 'device_id, device_name and platform are all required.', 400);
}
if (!preg_match('/^[a-f0-9-]{8,64}$/i', $deviceId)) {
    json_error('INVALID_BODY', 'device_id must be a UUID-like identifier.', 400);
}
if (strlen($deviceName) > 120) {
    json_error('INVALID_BODY', 'device_name is too long.', 400);
}
if ($accountKey !== '' && !preg_match('/^[a-f0-9]{64}$/', $accountKey)) {
    // Strict: the client derives exactly 64 hex chars. Anything else is a
    // malformed or hand-crafted request, not something to coerce.
    json_error('INVALID_BODY', 'account_key must be 64 hexadecimal characters.', 400);
}
if (strlen($platform) > 40) {
    json_error('INVALID_BODY', 'platform is too long.', 400);
}

// Scoped per device rather than per IP for the same reason described in
// config.php's LOGIN_RATE_LIMIT_MAX comment — this endpoint is cheap now
// (no outbound Xtream call left to protect), but the per-device/per-IP split
// is kept for consistency and because a stolen/replayed device_id hammering
// registrations is still worth bounding.
if (!check_rate_limit($deviceId, 'account_register_device', LOGIN_RATE_LIMIT_MAX, LOGIN_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many attempts from this device. Please try again later.', 429);
}
if (!check_rate_limit(client_ip(), 'account_register_ip', LOGIN_IP_RATE_LIMIT_MAX, LOGIN_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many attempts. Please try again later.', 429);
}

$pdo = db();
$pdo->beginTransaction();

try {
    // Precedence: an account_key identifies the account outright, so it
    // wins over a pairing code (which is only still accepted here for app
    // versions released before keys existed).
    $accountId = $accountKey !== '' ? $accountKey : null;
    if ($accountId === null && $pairingCode !== '') {
        $accountId = resolve_pairing_code($pairingCode);
    }

    if ($accountId !== null && $accountKey === '') {
        $existsStmt = $pdo->prepare('SELECT 1 FROM accounts WHERE account_id = :account_id');
        $existsStmt->execute(['account_id' => $accountId]);
        if ($existsStmt->fetchColumn() === false) {
            // The code resolved to an account_id that no longer exists
            // (deleted between the code being issued and used) — fall back
            // to a fresh account exactly as an invalid code would.
            $accountId = null;
        }
    }

    if ($accountId === null) {
        $accountId = generate_anonymous_account_id();
        $insertAccount = $pdo->prepare(
            'INSERT INTO accounts (account_id, status, last_login_at) VALUES (:account_id, \'active\', NOW())'
        );
        $insertAccount->execute(['account_id' => $accountId]);
    } elseif ($accountKey !== '') {
        // An account_key with no row yet is simply this user's first
        // sign-in on any device: create the account under that exact id
        // rather than minting a random one, which is what makes the same
        // credentials resolve to the same account on every device. One
        // statement for both cases — first sign-in inserts, every later
        // one just touches last_login_at.
        $upsertAccount = $pdo->prepare(
            'INSERT INTO accounts (account_id, status, last_login_at) VALUES (:account_id, \'active\', NOW())
             ON DUPLICATE KEY UPDATE last_login_at = NOW()'
        );
        $upsertAccount->execute(['account_id' => $accountId]);
    } else {
        $touchAccount = $pdo->prepare('UPDATE accounts SET last_login_at = NOW() WHERE account_id = :account_id');
        $touchAccount->execute(['account_id' => $accountId]);
    }

    $upsertDevice = $pdo->prepare(
        'INSERT INTO devices (account_id, device_id, device_name, platform, last_seen_at)
         VALUES (:account_id, :device_id, :device_name, :platform, NOW())
         ON DUPLICATE KEY UPDATE
            device_name = VALUES(device_name),
            platform = VALUES(platform),
            last_seen_at = NOW()'
    );
    $upsertDevice->execute([
        'account_id' => $accountId,
        'device_id' => $deviceId,
        'device_name' => $deviceName,
        'platform' => $platform,
    ]);

    $rawToken = bin2hex(random_bytes(32));
    $tokenHash = hash('sha256', $rawToken);
    $expiresAt = date('Y-m-d H:i:s', time() + DEVICE_TOKEN_TTL_DAYS * 86400);

    $insertToken = $pdo->prepare(
        'INSERT INTO device_tokens (account_id, device_id, token_hash, expires_at)
         VALUES (:account_id, :device_id, :token_hash, :expires_at)'
    );
    $insertToken->execute([
        'account_id' => $accountId,
        'device_id' => $deviceId,
        'token_hash' => $tokenHash,
        'expires_at' => $expiresAt,
    ]);

    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    json_error('INTERNAL_ERROR', 'Something went wrong. Please try again.', 500);
}

$profilesStmt = $pdo->prepare(
    'SELECT profile_id, name, avatar, is_kids, created_at, updated_at
     FROM profiles
     WHERE account_id = :account_id AND deleted_at IS NULL
     ORDER BY created_at ASC'
);
$profilesStmt->execute(['account_id' => $accountId]);
$profiles = array_map(static function (array $row): array {
    return [
        'profile_id' => $row['profile_id'],
        'name' => $row['name'],
        'avatar' => $row['avatar'],
        'is_kids' => (bool) $row['is_kids'],
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at'],
    ];
}, $profilesStmt->fetchAll());

json_success([
    'account_id' => $accountId,
    'device_token' => $rawToken,
    'expires_at' => $expiresAt,
    'profiles' => $profiles,
]);
