<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/db.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/uuid_validator.php';
require_once __DIR__ . '/../../lib/datetime_helper.php';
require_once __DIR__ . '/../../config.php';

require_api_key();
$auth = require_device_token();
$accountId = $auth['account_id'];

if (!check_rate_limit($auth['device_id'], 'profiles_write', WRITE_RATE_LIMIT_MAX, WRITE_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many requests. Please slow down.', 429);
}

$body = read_json_body();

$profileId = isset($body['profile_id']) ? (string) $body['profile_id'] : '';
$name = isset($body['name']) ? trim((string) $body['name']) : '';
$avatar = isset($body['avatar']) && $body['avatar'] !== '' ? (string) $body['avatar'] : 'default';
$isKids = !empty($body['is_kids']) ? 1 : 0;
$updatedAtRaw = isset($body['updated_at']) ? (string) $body['updated_at'] : '';

if (!is_valid_uuid($profileId)) {
    json_error('INVALID_BODY', 'profile_id must be a valid UUID.', 400);
}
if ($name === '' || mb_strlen($name) > 60) {
    json_error('INVALID_BODY', 'name is required and must be 60 characters or fewer.', 400);
}
if (mb_strlen($avatar) > 191) {
    json_error('INVALID_BODY', 'avatar is too long.', 400);
}
if ($updatedAtRaw === '') {
    json_error('INVALID_BODY', 'updated_at is required.', 400);
}
$updatedAt = parse_client_datetime($updatedAtRaw);

$pdo = db();

// A colliding profile_id could legitimately be this same account retrying an
// earlier call (offline queue replay), or — if it belongs to someone else —
// an attempt (deliberate or accidental) to overwrite another account's
// profile. Distinguish the two before writing anything.
$existingStmt = $pdo->prepare('SELECT account_id FROM profiles WHERE profile_id = :profile_id');
$existingStmt->execute(['profile_id' => $profileId]);
$existingAccountId = $existingStmt->fetchColumn();

if ($existingAccountId !== false && $existingAccountId !== $accountId) {
    json_error('PROFILE_ID_CONFLICT', 'This profile_id is already in use.', 409);
}

if ($existingAccountId === false) {
    // Only a genuinely new profile counts against the limit — a retried
    // create for a profile_id this account already owns must not.
    //
    // Note: there's a small unguarded race here if the same account fires
    // two "create" requests for two different new profiles at almost the
    // exact same moment (both could pass this COUNT check before either
    // commits, landing at 6 instead of 5). Accepted as a rare edge case for
    // this scale of app rather than adding SELECT ... FOR UPDATE locking —
    // consistent with the same call made for the schema not enforcing this
    // limit with a trigger.
    $countStmt = $pdo->prepare(
        'SELECT COUNT(*) FROM profiles WHERE account_id = :account_id AND deleted_at IS NULL'
    );
    $countStmt->execute(['account_id' => $accountId]);
    if ((int) $countStmt->fetchColumn() >= MAX_PROFILES_PER_ACCOUNT) {
        json_error('PROFILE_LIMIT_REACHED', 'Maximum of ' . MAX_PROFILES_PER_ACCOUNT . ' profiles reached.', 400);
    }
}

// Upsert guarded by last-write-wins on updated_at — deliberately never
// touches deleted_at here; deletion state only ever changes via delete.php.
$upsert = $pdo->prepare(
    'INSERT INTO profiles (profile_id, account_id, name, avatar, is_kids, created_at, updated_at)
     VALUES (:profile_id, :account_id, :name, :avatar, :is_kids, NOW(), :updated_at)
     ON DUPLICATE KEY UPDATE
        name = IF(VALUES(updated_at) > updated_at, VALUES(name), name),
        avatar = IF(VALUES(updated_at) > updated_at, VALUES(avatar), avatar),
        is_kids = IF(VALUES(updated_at) > updated_at, VALUES(is_kids), is_kids),
        updated_at = GREATEST(VALUES(updated_at), updated_at)'
);
$upsert->execute([
    'profile_id' => $profileId,
    'account_id' => $accountId,
    'name' => $name,
    'avatar' => $avatar,
    'is_kids' => $isKids,
    'updated_at' => $updatedAt,
]);

$resultStmt = $pdo->prepare(
    'SELECT profile_id, name, avatar, is_kids, created_at, updated_at
     FROM profiles WHERE profile_id = :profile_id'
);
$resultStmt->execute(['profile_id' => $profileId]);
$row = $resultStmt->fetch();

json_success([
    'profile' => [
        'profile_id' => $row['profile_id'],
        'name' => $row['name'],
        'avatar' => $row['avatar'],
        'is_kids' => (bool) $row['is_kids'],
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at'],
    ],
]);
