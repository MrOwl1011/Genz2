<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/db.php';

require_api_key();
$auth = require_device_token();

$stmt = db()->prepare(
    'SELECT profile_id, name, avatar, is_kids, favorites_cleared_at, history_cleared_at, created_at, updated_at
     FROM profiles
     WHERE account_id = :account_id AND deleted_at IS NULL
     ORDER BY created_at ASC'
);
$stmt->execute(['account_id' => $auth['account_id']]);
$rows = $stmt->fetchAll();

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
}, $rows);

json_success(['profiles' => $profiles]);
