<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/profile_ownership.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/db.php';
require_once __DIR__ . '/../../config.php';

require_api_key();
$auth = require_device_token();

if (!check_rate_limit($auth['device_id'], 'favorites_write', WRITE_RATE_LIMIT_MAX, WRITE_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many requests. Please slow down.', 429);
}

$body = read_json_body();

$profileId = isset($body['profile_id']) ? (string) $body['profile_id'] : '';
$streamId = isset($body['stream_id']) ? (string) $body['stream_id'] : '';
$streamType = isset($body['stream_type']) ? (string) $body['stream_type'] : '';

if ($profileId === '' || $streamId === '' || $streamType === '') {
    json_error('INVALID_BODY', 'profile_id, stream_id and stream_type are all required.', 400);
}

assert_profile_owned_by_account($profileId, $auth['account_id']);

// Plain DELETE — naturally idempotent, no last-write-wins concern (there's
// nothing to conflict with once a row is gone; a retried/duplicate remove
// call is just a 0-row no-op, still a success response).
$stmt = db()->prepare(
    'DELETE FROM favorites WHERE profile_id = :profile_id AND stream_id = :stream_id AND stream_type = :stream_type'
);
$stmt->execute([
    'profile_id' => $profileId,
    'stream_id' => $streamId,
    'stream_type' => $streamType,
]);

json_success(null);
