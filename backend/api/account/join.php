<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/pairing.php';
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

/**
 * Folds every non-deleted profile still under $oldAccountId into
 * $targetAccountId, oldest-created first. Two distinct outcomes depending
 * on whether the name already exists on the target account:
 *
 *   - Name collision ("Kids" exists on both sides): this is the same
 *     viewer on two devices, not two different people who happened to pick
 *     the same name — so their data is combined into the ONE existing
 *     target profile rather than kept as two separately-named copies. Every
 *     favorite either side had ends up on the merged profile; for a
 *     history row both sides have (same stream_id+stream_type), whichever
 *     side's `updated_at` is more recent wins, so neither device's more
 *     recent watch progress gets clobbered by the other's older entry. The
 *     now-empty old profile is soft-deleted (deleted_at), matching how the
 *     admin panel already deletes profiles elsewhere.
 *   - No collision: the profile moves across as-is (a plain account_id
 *     repoint), same as before — up to whatever room
 *     MAX_PROFILES_PER_ACCOUNT leaves. A merge never costs a profile slot
 *     (the target's count doesn't change), so the cap only ever applies to
 *     this non-colliding case.
 *
 * Returns [merged_count, left_behind_count] purely for the response —
 * left_behind_count is only ever nonzero when the target account was
 * already at MAX_PROFILES_PER_ACCOUNT and a non-colliding profile had
 * nowhere to go; it's left untouched on the now-orphaned old account,
 * recoverable later via the admin panel's "Copy Profile" if it ever
 * matters.
 */
function merge_profiles_into_target(PDO $pdo, string $oldAccountId, string $targetAccountId): array
{
    $oldProfilesStmt = $pdo->prepare(
        'SELECT profile_id, name FROM profiles
         WHERE account_id = :account_id AND deleted_at IS NULL
         ORDER BY created_at ASC'
    );
    $oldProfilesStmt->execute(['account_id' => $oldAccountId]);
    $oldProfiles = $oldProfilesStmt->fetchAll();

    if (empty($oldProfiles)) {
        return [0, 0];
    }

    $targetProfilesStmt = $pdo->prepare(
        'SELECT profile_id, name FROM profiles WHERE account_id = :account_id AND deleted_at IS NULL'
    );
    $targetProfilesStmt->execute(['account_id' => $targetAccountId]);
    $targetProfileIdByName = [];
    foreach ($targetProfilesStmt->fetchAll() as $row) {
        $targetProfileIdByName[$row['name']] = $row['profile_id'];
    }

    $mergedCount = 0;
    $leftBehindCount = 0;

    $moveProfileStmt = $pdo->prepare(
        'UPDATE profiles SET account_id = :target_account_id, updated_at = NOW()
         WHERE profile_id = :profile_id'
    );

    // Favorites carry no meaningful "which side is newer" signal (it's a
    // boolean, not a progress value) — ON DUPLICATE KEY UPDATE here is a
    // true no-op, just letting the INSERT silently skip rows the target
    // profile already has instead of erroring on the unique key.
    // Aliasing the source as `src` alone isn't enough: this INSERT selects
    // from the very table it inserts into, and confirmed live against the
    // real DB (see backend/diagnose_merge.php, since removed) that MySQL
    // still refuses to resolve a bare `id` in ON DUPLICATE KEY UPDATE
    // ("Column 'id' in UPDATE is ambiguous", SQLSTATE 23000) unless the
    // updated column is *also* explicitly qualified with the target
    // table's own name.
    $mergeFavoritesStmt = $pdo->prepare(
        'INSERT INTO favorites (profile_id, stream_id, stream_type, title, poster_url, raw_data, created_at, updated_at)
         SELECT :target_profile_id, stream_id, stream_type, title, poster_url, raw_data, created_at, updated_at
         FROM favorites AS src WHERE src.profile_id = :old_profile_id
         ON DUPLICATE KEY UPDATE favorites.id = favorites.id'
    );
    // History DOES carry a meaningful signal (position_seconds is real
    // watch progress) — keep whichever side was touched more recently.
    // Same self-referencing INSERT...SELECT as favorites above, same fix:
    // every bare column reference below is qualified with `history.` so it
    // unambiguously means "the existing target row", not "the source row
    // being selected from the same table" — confirmed live, see above.
    $mergeHistoryStmt = $pdo->prepare(
        'INSERT INTO history (profile_id, stream_id, stream_type, episode_id, series_id, title, poster_url, position_seconds, duration_seconds, raw_data, updated_at)
         SELECT :target_profile_id, stream_id, stream_type, episode_id, series_id, title, poster_url, position_seconds, duration_seconds, raw_data, updated_at
         FROM history AS src WHERE src.profile_id = :old_profile_id
         ON DUPLICATE KEY UPDATE
           position_seconds = IF(VALUES(updated_at) > history.updated_at, VALUES(position_seconds), history.position_seconds),
           duration_seconds = IF(VALUES(updated_at) > history.updated_at, VALUES(duration_seconds), history.duration_seconds),
           episode_id = IF(VALUES(updated_at) > history.updated_at, VALUES(episode_id), history.episode_id),
           series_id = IF(VALUES(updated_at) > history.updated_at, VALUES(series_id), history.series_id),
           raw_data = IF(VALUES(updated_at) > history.updated_at, VALUES(raw_data), history.raw_data),
           updated_at = GREATEST(history.updated_at, VALUES(updated_at))'
    );
    $deleteFavoritesStmt = $pdo->prepare('DELETE FROM favorites WHERE profile_id = :profile_id');
    $deleteHistoryStmt = $pdo->prepare('DELETE FROM history WHERE profile_id = :profile_id');
    $softDeleteProfileStmt = $pdo->prepare(
        'UPDATE profiles SET deleted_at = NOW(), updated_at = NOW() WHERE profile_id = :profile_id'
    );

    foreach ($oldProfiles as $profile) {
        $name = (string) $profile['name'];
        $oldProfileId = $profile['profile_id'];

        if (isset($targetProfileIdByName[$name])) {
            $targetProfileId = $targetProfileIdByName[$name];
            $mergeFavoritesStmt->execute([
                'target_profile_id' => $targetProfileId,
                'old_profile_id' => $oldProfileId,
            ]);
            $mergeHistoryStmt->execute([
                'target_profile_id' => $targetProfileId,
                'old_profile_id' => $oldProfileId,
            ]);
            $deleteFavoritesStmt->execute(['profile_id' => $oldProfileId]);
            $deleteHistoryStmt->execute(['profile_id' => $oldProfileId]);
            $softDeleteProfileStmt->execute(['profile_id' => $oldProfileId]);
            $mergedCount++;
            continue;
        }

        if (count($targetProfileIdByName) >= MAX_PROFILES_PER_ACCOUNT) {
            $leftBehindCount++;
            continue;
        }

        $moveProfileStmt->execute([
            'target_account_id' => $targetAccountId,
            'profile_id' => $oldProfileId,
        ]);
        $targetProfileIdByName[$name] = $oldProfileId;
        $mergedCount++;
    }

    return [$mergedCount, $leftBehindCount];
}

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
