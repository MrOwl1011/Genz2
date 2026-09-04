<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/db.php';
require_once __DIR__ . '/../../config.php';

require_api_key();
$auth = require_device_token();
$accountId = $auth['account_id'];

if (!check_rate_limit($auth['device_id'], 'devices_write', WRITE_RATE_LIMIT_MAX, WRITE_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many requests. Please slow down.', 429);
}

$body = read_json_body();
$targetDeviceId = isset($body['device_id']) ? (string) $body['device_id'] : '';
if ($targetDeviceId === '') {
    json_error('INVALID_BODY', 'device_id is required.', 400);
}

$pdo = db();
$pdo->beginTransaction();

try {
    // Revoke first (belt-and-suspenders — any token for this device stops
    // working immediately even if the DELETE below somehow doesn't run),
    // then remove the device row itself so it drops out of the user's list.
    // Both scoped to account_id — a request for a device_id that exists but
    // belongs to a different account affects 0 rows, same as an unknown one.
    $revoke = $pdo->prepare(
        'UPDATE device_tokens SET revoked_at = NOW()
         WHERE account_id = :account_id AND device_id = :device_id AND revoked_at IS NULL'
    );
    $revoke->execute(['account_id' => $accountId, 'device_id' => $targetDeviceId]);

    $delete = $pdo->prepare(
        'DELETE FROM devices WHERE account_id = :account_id AND device_id = :device_id'
    );
    $delete->execute(['account_id' => $accountId, 'device_id' => $targetDeviceId]);
    $deletedCount = $delete->rowCount();

    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    json_error('INTERNAL_ERROR', 'Something went wrong. Please try again.', 500);
}

if ($deletedCount === 0) {
    json_error('DEVICE_NOT_FOUND', 'Device not found.', 404);
}

json_success(null);
