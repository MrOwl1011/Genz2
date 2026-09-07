<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/pairing.php';
require_once __DIR__ . '/../../lib/profile_merge.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/db.php';

/**
 * Moves the calling device from its current account onto the account a
 * pairing code was issued for — for a device that already registered
 * (register.php, with no code) and only afterwards got a code from another
 * device to join. register.php's own pairing_code parameter covers the more
 * common case (entering a code before the very first registration); this
 * covers "I already opened the app once, and only now got the code."
 *
 * Also folds in any profiles this device's *old* account already had (see
 * merge_profiles_into_target() below) — this device is the one whose
 * profiles/favorites/history would otherwise be silently stranded by a
 * plain device move, which is exactly the "my profile disappeared when I
 * entered the code" report that this function exists to fix. A profile
 * whose name doesn't already exist on the target account is simply
 * repointed (favorites/history are keyed by profile_id, not account_id —
 * see schema.sql — so they follow automatically); a same-named profile on
 * both sides is treated as the same viewer and has its data actually
 * merged into the one existing profile instead of kept as a duplicate.
 */
require_api_key();
$auth = require_device_token();

$body = read_json_body();
$code = isset($body['code']) ? trim((string) $body['code']) : '';

if ($code === '') {
    json_error('INVALID_BODY', 'code is required.', 400);
}

// Codes are only PAIRING_CODE_LENGTH (4) chars — see pairing.php's doc
// comment — so unlike most rate limits here, this one exists specifically
// to keep brute-forcing a live code impractical, not just to bound abuse.
// Scoped by device_id: a caller already needed a valid device token
// (require_device_token() above) to reach this point at all, so this is
// bounding a registered device's guesses, not an anonymous IP's.
if (!check_rate_limit($auth['device_id'], 'account_join', PAIRING_JOIN_RATE_LIMIT_MAX, PAIRING_JOIN_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many attempts. Please try again later.', 429);
}

$targetAccountId = resolve_pairing_code($code);
if ($targetAccountId === null) {
    json_error('INVALID_CODE', 'This code is invalid or has expired.', 404);
}

if ($targetAccountId === $auth['account_id']) {
    json_error('ALREADY_JOINED', 'This device is already on that account.', 409);
}

// merge_profiles_into_target() now lives in lib/profile_merge.php — it is
// shared with account/merge.php and must not be duplicated here.


$pdo = db();
$pdo->beginTransaction();

try {
    [$mergedCount, $leftBehindCount] = merge_profiles_into_target($pdo, $auth['account_id'], $targetAccountId);

    // This device_id may already have a row under the target account from a
    // previous life (e.g. it joined, left, and is rejoining) — repoint
    // rather than insert, exactly as register.php's ON DUPLICATE KEY UPDATE
    // does for a fresh registration.
    $upsertDevice = $pdo->prepare(
        'INSERT INTO devices (account_id, device_id, device_name, platform, last_seen_at)
         SELECT :target_account_id, device_id, device_name, platform, NOW()
         FROM devices WHERE account_id = :old_account_id AND device_id = :device_id
         ON DUPLICATE KEY UPDATE last_seen_at = NOW()'
    );
    $upsertDevice->execute([
        'target_account_id' => $targetAccountId,
        'old_account_id' => $auth['account_id'],
        'device_id' => $auth['device_id'],
    ]);

    $deleteOldDevice = $pdo->prepare(
        'DELETE FROM devices WHERE account_id = :account_id AND device_id = :device_id'
    );
    $deleteOldDevice->execute([
        'account_id' => $auth['account_id'],
        'device_id' => $auth['device_id'],
    ]);

    // Revoke every token this device held on the old account and mint a
    // fresh one on the new account, rather than repointing the existing
    // token row — the client is about to receive a brand-new token anyway,
    // and leaving stale ones around revoked is simpler to reason about than
    // trying to update a row the client already has a copy of.
    $revokeOld = $pdo->prepare(
        'UPDATE device_tokens SET revoked_at = NOW()
         WHERE account_id = :account_id AND device_id = :device_id AND revoked_at IS NULL'
    );
    $revokeOld->execute([
        'account_id' => $auth['account_id'],
        'device_id' => $auth['device_id'],
    ]);

    $rawToken = bin2hex(random_bytes(32));
    $tokenHash = hash('sha256', $rawToken);
    $expiresAt = date('Y-m-d H:i:s', time() + DEVICE_TOKEN_TTL_DAYS * 86400);

    $insertToken = $pdo->prepare(
        'INSERT INTO device_tokens (account_id, device_id, token_hash, expires_at)
         VALUES (:account_id, :device_id, :token_hash, :expires_at)'
    );
    $insertToken->execute([
        'account_id' => $targetAccountId,
        'device_id' => $auth['device_id'],
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
$profilesStmt->execute(['account_id' => $targetAccountId]);
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
    'account_id' => $targetAccountId,
    'device_token' => $rawToken,
    'expires_at' => $expiresAt,
    'profiles' => $profiles,
    // See merge_profiles_into_target()'s doc comment — merged_profiles is
    // this device's own profile(s) that just got folded into the target
    // account; profiles_left_behind is only ever nonzero if the target
    // account was already at MAX_PROFILES_PER_ACCOUNT.
    'merged_profiles' => $mergedCount,
    'profiles_left_behind' => $leftBehindCount,
]);
