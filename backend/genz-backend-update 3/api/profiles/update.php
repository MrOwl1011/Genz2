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
$updatedAtRaw = isset($body['updated_at']) ? (string) $body['updated_at'] : '';

if (!is_valid_uuid($profileId)) {
    json_error('INVALID_BODY', 'profile_id must be a valid UUID.', 400);
}
if ($updatedAtRaw === '') {
    json_error('INVALID_BODY', 'updated_at is required.', 400);
}
$updatedAt = parse_client_datetime($updatedAtRaw);

$pdo = db();

$existingStmt = $pdo->prepare(
    'SELECT account_id, name, avatar, is_kids, updated_at
     FROM profiles WHERE profile_id = :profile_id AND deleted_at IS NULL'
);
$existingStmt->execute(['profile_id' => $profileId]);
$existing = $existingStmt->fetch();

if ($existing === false) {
    json_error('PROFILE_NOT_FOUND', 'Profile not found.', 404);
}
if ($existing['account_id'] !== $accountId) {
    json_error('PROFILE_NOT_FOUND', 'Profile not found.', 404); // don't leak that it belongs to someone else
}

// Last-write-wins: if the server already holds a newer version than this
// request, silently keep the server's version and return it as-is — this is
// a normal, expected outcome of the sync engine replaying a since-superseded
// offline mutation, not an error.
if (strtotime($updatedAt) <= strtotime((string) $existing['updated_at'])) {
    json_success([
        'profile' => [
            'profile_id' => $profileId,
            'name' => $existing['name'],
            'avatar' => $existing['avatar'],
            'is_kids' => (bool) $existing['is_kids'],
            'updated_at' => $existing['updated_at'],
        ],
    ]);
}

$name = isset($body['name']) ? trim((string) $body['name']) : (string) $existing['name'];
$avatar = isset($body['avatar']) && $body['avatar'] !== '' ? (string) $body['avatar'] : (string) $existing['avatar'];
$isKids = array_key_exists('is_kids', $body) ? (!empty($body['is_kids']) ? 1 : 0) : (int) $existing['is_kids'];

if ($name === '' || mb_strlen($name) > 60) {
    json_error('INVALID_BODY', 'name must be 1-60 characters.', 400);
}
if (mb_strlen($avatar) > 191) {
    json_error('INVALID_BODY', 'avatar is too long.', 400);
}

$update = $pdo->prepare(
    'UPDATE profiles
     SET name = :name, avatar = :avatar, is_kids = :is_kids, updated_at = :updated_at
     WHERE profile_id = :profile_id AND account_id = :account_id'
);
$update->execute([
    'name' => $name,
    'avatar' => $avatar,
    'is_kids' => $isKids,
    'updated_at' => $updatedAt,
    'profile_id' => $profileId,
    'account_id' => $accountId,
]);

json_success([
    'profile' => [
        'profile_id' => $profileId,
        'name' => $name,
        'avatar' => $avatar,
        'is_kids' => (bool) $isKids,
        'updated_at' => $updatedAt,
    ],
]);
