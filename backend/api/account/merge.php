<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/profile_merge.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/db.php';
require_once __DIR__ . '/../../config.php';

/**
 * Folds the account a device *used* to be on into the one it is on now,
 * carrying its profiles, favorites and history across.
 *
 * This is what replaces pairing codes. It serves two flows, which are the
 * same operation from the server's point of view:
 *
 *   1. Migration. An install that predates credential-derived account keys
 *      has a random anonymous account. On first launch after the update the
 *      app registers its computed account_key (a new, empty account), then
 *      calls this with the anonymous token it still holds. One time, no
 *      user action.
 *   2. Credential change. The user's IPTV password changed, so the app now
 *      computes a different key and lands on a different account. Same
 *      call, same effect: the previous account's data follows them.
 *
 * Authorization requires holding valid device tokens for BOTH accounts —
 * the current one in the Authorization header, the previous one in the
 * body — AND both tokens must belong to the same device_id. That last
 * constraint is what stops a leaked token being used to vacuum somebody
 * else's profiles into an attacker's account: proving you hold a token is
 * not enough, you have to be the same device that holds both.
 *
 * Idempotent by construction. Merging an already-merged (now empty)
 * account is a no-op returning merged_profiles = 0, so a client that
 * retries after a dropped connection cannot double-apply anything.
 */
require_api_key();
$auth = require_device_token();

if (!check_rate_limit($auth['device_id'], 'account_merge', LOGIN_RATE_LIMIT_MAX, LOGIN_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many attempts. Please try again later.', 429);
}

$body = read_json_body();
$previousToken = isset($body['previous_token']) ? trim((string) $body['previous_token']) : '';

if ($previousToken === '') {
    json_error('INVALID_BODY', 'previous_token is required.', 400);
}

$pdo = db();

// Resolve the previous token by hash, exactly as require_device_token()
// does for the header — the raw token is never stored, only its SHA-256.
$prevStmt = $pdo->prepare(
    'SELECT account_id, device_id, expires_at, revoked_at
     FROM device_tokens WHERE token_hash = :token_hash'
);
$prevStmt->execute(['token_hash' => hash('sha256', $previousToken)]);
$prev = $prevStmt->fetch();

if ($prev === false) {
    json_error('INVALID_PREVIOUS_TOKEN', 'That previous session is not recognized.', 404);
}
if ($prev['revoked_at'] !== null) {
    json_error('INVALID_PREVIOUS_TOKEN', 'That previous session has already been ended.', 409);
}
if (strtotime((string) $prev['expires_at']) < time()) {
    json_error('INVALID_PREVIOUS_TOKEN', 'That previous session has expired.', 409);
}

// The security constraint this endpoint rests on — see the doc comment.
if ($prev['device_id'] !== $auth['device_id']) {
    json_error('DEVICE_MISMATCH', 'That previous session belongs to a different device.', 403);
}

$oldAccountId = (string) $prev['account_id'];
$newAccountId = $auth['account_id'];

// Already the same account: nothing to do, and definitely nothing to
// merge into itself (which would soft-delete profiles against themselves).
if ($oldAccountId === $newAccountId) {
    json_success([
        'account_id' => $newAccountId,
        'merged_profiles' => 0,
        'profiles_left_behind' => 0,
        'already_merged' => true,
    ]);
}

$pdo->beginTransaction();

try {
    [$mergedCount, $leftBehindCount] = merge_profiles_into_target($pdo, $oldAccountId, $newAccountId);

    // Retire the old account's session for this device. The account row
    // itself is deliberately left in place rather than deleted: profiles
    // that didn't fit under MAX_PROFILES_PER_ACCOUNT are still attached to
    // it, and the admin panel can still reach them.
    $revokeOld = $pdo->prepare(
        'UPDATE device_tokens SET revoked_at = NOW()
         WHERE account_id = :account_id AND device_id = :device_id AND revoked_at IS NULL'
    );
    $revokeOld->execute([
        'account_id' => $oldAccountId,
        'device_id' => $auth['device_id'],
    ]);

    $dropOldDevice = $pdo->prepare(
        'DELETE FROM devices WHERE account_id = :account_id AND device_id = :device_id'
    );
    $dropOldDevice->execute([
        'account_id' => $oldAccountId,
        'device_id' => $auth['device_id'],
    ]);

    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    json_error('INTERNAL_ERROR', 'Something went wrong. Please try again.', 500);
}

$profilesStmt = $pdo->prepare(
    'SELECT profile_id, name, avatar, is_kids, favorites_cleared_at, history_cleared_at, created_at, updated_at
     FROM profiles
     WHERE account_id = :account_id AND deleted_at IS NULL
     ORDER BY created_at ASC'
);
$profilesStmt->execute(['account_id' => $newAccountId]);
$profiles = array_map(static function (array $row): array {
    return [
        'profile_id' => $row['profile_id'],
        'name' => $row['name'],
        'avatar' => $row['avatar'],
        'is_kids' => (bool) $row['is_kids'],
        'favorites_cleared_at' => $row['favorites_cleared_at'],
        'history_cleared_at' => $row['history_cleared_at'],
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at'],
    ];
}, $profilesStmt->fetchAll());

json_success([
    'account_id' => $newAccountId,
    'profiles' => $profiles,
    'merged_profiles' => $mergedCount,
    'profiles_left_behind' => $leftBehindCount,
    'already_merged' => false,
]);
