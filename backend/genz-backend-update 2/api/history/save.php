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

const HISTORY_VALID_STREAM_TYPES = ['movie', 'series', 'live'];

require_api_key();
$auth = require_device_token();

// History saves happen far more often than any other write in this app
// (every ~30s while a video plays — see PlayerScreen._saveCurrentPosition),
// so it gets its own, more generous rate-limit bucket rather than sharing
// favorites'/profiles' tighter one.
if (!check_rate_limit($auth['device_id'], 'history_write', WRITE_RATE_LIMIT_MAX * 3, WRITE_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many requests. Please slow down.', 429);
}

$body = read_json_body();

$profileId = isset($body['profile_id']) ? (string) $body['profile_id'] : '';
$streamId = isset($body['stream_id']) ? (string) $body['stream_id'] : '';
$streamType = isset($body['stream_type']) ? (string) $body['stream_type'] : '';
$episodeId = isset($body['episode_id']) && $body['episode_id'] !== '' ? (string) $body['episode_id'] : null;
$seriesId = isset($body['series_id']) && $body['series_id'] !== '' ? (string) $body['series_id'] : null;
$title = isset($body['title']) ? trim((string) $body['title']) : '';
$posterUrl = isset($body['poster_url']) ? (string) $body['poster_url'] : null;
$positionSeconds = isset($body['position_seconds']) ? (int) $body['position_seconds'] : 0;
$durationSeconds = isset($body['duration_seconds']) ? (int) $body['duration_seconds'] : 0;
$rawData = isset($body['raw_data']) && is_array($body['raw_data']) ? $body['raw_data'] : null;
$updatedAtRaw = isset($body['updated_at']) ? (string) $body['updated_at'] : '';

if ($profileId === '') {
    json_error('INVALID_BODY', 'profile_id is required.', 400);
}
if ($streamId === '' || mb_strlen($streamId) > 64) {
    json_error('INVALID_BODY', 'stream_id is required and must be 64 characters or fewer.', 400);
}
if (!in_array($streamType, HISTORY_VALID_STREAM_TYPES, true)) {
    json_error('INVALID_BODY', 'stream_type must be one of: movie, series, live.', 400);
}
if ($title === '' || mb_strlen($title) > 255) {
    json_error('INVALID_BODY', 'title is required and must be 255 characters or fewer.', 400);
}
if ($positionSeconds < 0 || $durationSeconds < 0) {
    json_error('INVALID_BODY', 'position_seconds/duration_seconds cannot be negative.', 400);
}
if ($updatedAtRaw === '') {
    json_error('INVALID_BODY', 'updated_at is required.', 400);
}
$updatedAt = parse_client_datetime($updatedAtRaw);

assert_profile_owned_by_account($profileId, $auth['account_id']);

// Upsert guarded by last-write-wins on updated_at — unique key is
// (profile_id, stream_id, stream_type); deliberately not including
// episode_id in that key, matching how the existing Dart HistoryItem.id is
// already the sole per-watchable-unit dedup key today (see schema.sql).
$stmt = db()->prepare(
    'INSERT INTO history (profile_id, stream_id, stream_type, episode_id, series_id,
                           title, poster_url, position_seconds, duration_seconds, raw_data, updated_at)
     VALUES (:profile_id, :stream_id, :stream_type, :episode_id, :series_id,
             :title, :poster_url, :position_seconds, :duration_seconds, :raw_data, :updated_at)
     ON DUPLICATE KEY UPDATE
        episode_id = IF(VALUES(updated_at) > updated_at, VALUES(episode_id), episode_id),
        series_id = IF(VALUES(updated_at) > updated_at, VALUES(series_id), series_id),
        title = IF(VALUES(updated_at) > updated_at, VALUES(title), title),
        poster_url = IF(VALUES(updated_at) > updated_at, VALUES(poster_url), poster_url),
        position_seconds = IF(VALUES(updated_at) > updated_at, VALUES(position_seconds), position_seconds),
        duration_seconds = IF(VALUES(updated_at) > updated_at, VALUES(duration_seconds), duration_seconds),
        raw_data = IF(VALUES(updated_at) > updated_at, VALUES(raw_data), raw_data),
        updated_at = GREATEST(VALUES(updated_at), updated_at)'
);
$stmt->execute([
    'profile_id' => $profileId,
    'stream_id' => $streamId,
    'stream_type' => $streamType,
    'episode_id' => $episodeId,
    'series_id' => $seriesId,
    'title' => $title,
    'poster_url' => $posterUrl,
    'position_seconds' => $positionSeconds,
    'duration_seconds' => $durationSeconds,
    'raw_data' => $rawData !== null ? json_encode($rawData) : null,
    'updated_at' => $updatedAt,
]);

// The unique key above is per-episode (stream_id), not per-series, so
// watching episode 2 then episode 5 previously left both rows sitting in
// the table forever — every sync pull re-merged the old episode back in
// alongside the new one. Only one history entry per series should ever
// exist: the most recently watched episode. Guarded by updated_at so an
// out-of-order/stale write (e.g. a delayed sync of an older watch) can't
// wipe out a genuinely newer episode's row — only rows actually older
// than this write get removed, which also correctly handles a user
// deliberately re-watching an earlier episode later (that becomes the
// newest updated_at and this cleanup then removes the now-stale sibling).
if ($streamType === 'series' && $seriesId !== null) {
    $cleanupStmt = db()->prepare(
        'DELETE FROM history
         WHERE profile_id = :profile_id
           AND stream_type = :stream_type
           AND series_id = :series_id
           AND stream_id != :stream_id
           AND updated_at < :updated_at'
    );
    $cleanupStmt->execute([
        'profile_id' => $profileId,
        'stream_type' => $streamType,
        'series_id' => $seriesId,
        'stream_id' => $streamId,
        'updated_at' => $updatedAt,
    ]);
}

json_success(null);
