<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/profile_ownership.php';
require_once __DIR__ . '/../../lib/db.php';

require_api_key();
$auth = require_device_token();

$body = read_json_body();
$profileId = isset($body['profile_id']) ? (string) $body['profile_id'] : '';
if ($profileId === '') {
    json_error('INVALID_BODY', 'profile_id is required.', 400);
}
assert_profile_owned_by_account($profileId, $auth['account_id']);

// LIMIT 50 mirrors UserPrefsProvider's existing in-app history cap
// (lib/providers/user_prefs_provider.dart's saveHistory()).
$stmt = db()->prepare(
    'SELECT stream_id, stream_type, episode_id, series_id, title, poster_url,
            position_seconds, duration_seconds, raw_data, updated_at
     FROM history WHERE profile_id = :profile_id
     ORDER BY updated_at DESC LIMIT 50'
);
$stmt->execute(['profile_id' => $profileId]);

$history = array_map(static function (array $row): array {
    return [
        'stream_id' => $row['stream_id'],
        'stream_type' => $row['stream_type'],
        'episode_id' => $row['episode_id'],
        'series_id' => $row['series_id'],
        'title' => $row['title'],
        'poster_url' => $row['poster_url'],
        'position_seconds' => (int) $row['position_seconds'],
        'duration_seconds' => (int) $row['duration_seconds'],
        'raw_data' => $row['raw_data'] !== null ? json_decode($row['raw_data'], true) : null,
        'updated_at' => $row['updated_at'],
    ];
}, $stmt->fetchAll());

json_success(['history' => $history]);
