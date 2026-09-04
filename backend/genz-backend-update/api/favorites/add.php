<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/profile_ownership.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/datetime_helper.php';
require_once __DIR__ . '/../../lib/db.php';
require_once __DIR__ . '/../../config.php';

const VALID_STREAM_TYPES = ['movie', 'series', 'live'];

require_api_key();
$auth = require_device_token();

if (!check_rate_limit($auth['device_id'], 'favorites_write', WRITE_RATE_LIMIT_MAX, WRITE_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many requests. Please slow down.', 429);
}

$body = read_json_body();

$profileId = isset($body['profile_id']) ? (string) $body['profile_id'] : '';
$streamId = isset($body['stream_id']) ? (string) $body['stream_id'] : '';
$streamType = isset($body['stream_type']) ? (string) $body['stream_type'] : '';
$title = isset($body['title']) ? trim((string) $body['title']) : '';
$posterUrl = isset($body['poster_url']) ? (string) $body['poster_url'] : null;
$rawData = isset($body['raw_data']) && is_array($body['raw_data']) ? $body['raw_data'] : null;
$updatedAtRaw = isset($body['updated_at']) ? (string) $body['updated_at'] : '';

if ($profileId === '') {
    json_error('INVALID_BODY', 'profile_id is required.', 400);
}
if ($streamId === '' || mb_strlen($streamId) > 64) {
    json_error('INVALID_BODY', 'stream_id is required and must be 64 characters or fewer.', 400);
}
if (!in_array($streamType, VALID_STREAM_TYPES, true)) {
    json_error('INVALID_BODY', 'stream_type must be one of: movie, series, live.', 400);
}
if ($title === '' || mb_strlen($title) > 255) {
    json_error('INVALID_BODY', 'title is required and must be 255 characters or fewer.', 400);
}
if ($posterUrl !== null && strlen($posterUrl) > 500) {
    json_error('INVALID_BODY', 'poster_url is too long.', 400);
}
if ($updatedAtRaw === '') {
    json_error('INVALID_BODY', 'updated_at is required.', 400);
}
$updatedAt = parse_client_datetime($updatedAtRaw);

assert_profile_owned_by_account($profileId, $auth['account_id']);

// Upsert guarded by last-write-wins on updated_at, same mechanic as
// profiles/create.php — unique key is (profile_id, stream_id, stream_type).
$stmt = db()->prepare(
    'INSERT INTO favorites (profile_id, stream_id, stream_type, title, poster_url, raw_data, updated_at)
     VALUES (:profile_id, :stream_id, :stream_type, :title, :poster_url, :raw_data, :updated_at)
     ON DUPLICATE KEY UPDATE
        title = IF(VALUES(updated_at) > updated_at, VALUES(title), title),
        poster_url = IF(VALUES(updated_at) > updated_at, VALUES(poster_url), poster_url),
        raw_data = IF(VALUES(updated_at) > updated_at, VALUES(raw_data), raw_data),
        updated_at = GREATEST(VALUES(updated_at), updated_at)'
);
$stmt->execute([
    'profile_id' => $profileId,
    'stream_id' => $streamId,
    'stream_type' => $streamType,
    'title' => $title,
    'poster_url' => $posterUrl,
    'raw_data' => $rawData !== null ? json_encode($rawData) : null,
    'updated_at' => $updatedAt,
]);

json_success(null);
