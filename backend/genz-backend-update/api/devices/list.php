<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/db.php';

require_api_key();
$auth = require_device_token();

$stmt = db()->prepare(
    'SELECT device_id, device_name, platform, last_seen_at, created_at
     FROM devices WHERE account_id = :account_id
     ORDER BY last_seen_at DESC'
);
$stmt->execute(['account_id' => $auth['account_id']]);

$currentDeviceId = $auth['device_id'];
$devices = array_map(static function (array $row) use ($currentDeviceId): array {
    return [
        'device_id' => $row['device_id'],
        'device_name' => $row['device_name'],
        'platform' => $row['platform'],
        'last_seen_at' => $row['last_seen_at'],
        'created_at' => $row['created_at'],
        'is_current' => $row['device_id'] === $currentDeviceId,
    ];
}, $stmt->fetchAll());

json_success(['devices' => $devices]);
