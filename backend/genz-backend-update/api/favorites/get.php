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

$stmt = db()->prepare(
    'SELECT stream_id, stream_type, title, poster_url, raw_data, updated_at
     FROM favorites WHERE profile_id = :profile_id ORDER BY created_at ASC'
);
$stmt->execute(['profile_id' => $profileId]);

$favorites = array_map(static function (array $row): array {
    return [
        'stream_id' => $row['stream_id'],
        'stream_type' => $row['stream_type'],
        'title' => $row['title'],
        'poster_url' => $row['poster_url'],
        // MySQL JSON columns come back from PDO as raw JSON text, not
        // auto-decoded — decode here so it nests as a real object in the
        // response instead of a double-encoded string.
        'raw_data' => $row['raw_data'] !== null ? json_decode($row['raw_data'], true) : null,
        'updated_at' => $row['updated_at'],
    ];
}, $stmt->fetchAll());

json_success(['favorites' => $favorites]);
