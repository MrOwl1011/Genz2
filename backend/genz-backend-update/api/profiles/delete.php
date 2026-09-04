<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/db.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/uuid_validator.php';
require_once __DIR__ . '/../../config.php';

require_api_key();
$auth = require_device_token();
$accountId = $auth['account_id'];

if (!check_rate_limit($auth['device_id'], 'profiles_write', WRITE_RATE_LIMIT_MAX, WRITE_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many requests. Please slow down.', 429);
}

$body = read_json_body();
$profileId = isset($body['profile_id']) ? (string) $body['profile_id'] : '';

if (!is_valid_uuid($profileId)) {
    json_error('INVALID_BODY', 'profile_id must be a valid UUID.', 400);
}

$pdo = db();

// Soft delete only — associated favorites/history rows are left physically
// intact (the admin panel gets separate, explicit actions to purge those;
// see the original spec's admin capability list). Scoping the UPDATE to
// account_id as well as profile_id means a request for a profile that
// exists but belongs to someone else affects 0 rows, same as a genuinely
// unknown profile_id — no distinction leaked either way.
$stmt = $pdo->prepare(
    'UPDATE profiles SET deleted_at = NOW(), updated_at = NOW()
     WHERE profile_id = :profile_id AND account_id = :account_id AND deleted_at IS NULL'
);
$stmt->execute([
    'profile_id' => $profileId,
    'account_id' => $accountId,
]);

if ($stmt->rowCount() === 0) {
    json_error('PROFILE_NOT_FOUND', 'Profile not found.', 404);
}

json_success(null);
