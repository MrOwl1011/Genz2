<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/pairing.php';

/**
 * Issues a code the caller's account can be joined with — see pairing.php's
 * class doc comment. Requires a device token (this device already has an
 * account); the code identifies that account, nothing about the device or
 * the Xtream service behind it.
 */
require_api_key();
$auth = require_device_token();

$result = generate_pairing_code($auth['account_id']);

json_success([
    'code' => $result['code'],
    'expires_at' => $result['expires_at'],
]);
