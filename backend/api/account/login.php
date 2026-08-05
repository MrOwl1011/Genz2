<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/rate_limit.php';
require_once __DIR__ . '/../../lib/account_id.php';
require_once __DIR__ . '/../../lib/xtream_client.php';
require_once __DIR__ . '/../../lib/db.php';

require_api_key();

if (!check_rate_limit(client_ip(), 'account_login', LOGIN_RATE_LIMIT_MAX, LOGIN_RATE_LIMIT_WINDOW)) {
    json_error('RATE_LIMITED', 'Too many login attempts. Please try again later.', 429);
}

$body = read_json_body();

$serverUrl = isset($body['server_url']) ? (string) $body['server_url'] : '';
$username = isset($body['username']) ? (string) $body['username'] : '';
$password = isset($body['password']) ? (string) $body['password'] : '';
$deviceId = isset($body['device_id']) ? (string) $body['device_id'] : '';
$deviceName = isset($body['device_name']) ? (string) $body['device_name'] : '';
$platform = isset($body['platform']) ? (string) $body['platform'] : '';

if ($serverUrl === '' || $username === '' || $password === '' || $deviceId === '' || $deviceName === '' || $platform === '') {
    json_error('INVALID_BODY', 'server_url, username, password, device_id, device_name and platform are all required.', 400);
}

if (strlen($serverUrl) > 500) {
    json_error('INVALID_BODY', 'server_url is too long.', 400);
}
if (strlen($username) > 191) {
    json_error('INVALID_BODY', 'username is too long.', 400);
}
if (!preg_match('/^[a-f0-9-]{8,64}$/i', $deviceId)) {
    json_error('INVALID_BODY', 'device_id must be a UUID-like identifier.', 400);
}
if (strlen($deviceName) > 120) {
    json_error('INVALID_BODY', 'device_name is too long.', 400);
}
if (strlen($platform) > 40) {
    json_error('INVALID_BODY', 'platform is too long.', 400);
}

// Independently re-validate against the user's own Xtream panel — never
// trust the client's say-so that these credentials are correct. Throws
// RuntimeException with a user-facing message on any failure.
try {
    validate_xtream_login($serverUrl, $username, $password);
} catch (RuntimeException $e) {
    json_error('XTREAM_AUTH_FAILED', $e->getMessage(), 401);
}

$accountId = compute_account_id($serverUrl, $username);
$normalizedServerUrl = normalize_server_url($serverUrl);
$normalizedUsername = normalize_username($username);

$pdo = db();
$pdo->beginTransaction();

try {
    $upsertAccount = $pdo->prepare(
        'INSERT INTO accounts (account_id, server_url, username, last_login_at)
         VALUES (:account_id, :server_url, :username, NOW())
         ON DUPLICATE KEY UPDATE
            server_url = VALUES(server_url),
            username = VALUES(username),
            last_login_at = NOW()'
    );
    $upsertAccount->execute([
        'account_id' => $accountId,
        'server_url' => $normalizedServerUrl,
        'username' => $normalizedUsername,
    ]);

    $statusStmt = $pdo->prepare('SELECT status FROM accounts WHERE account_id = :account_id');
    $statusStmt->execute(['account_id' => $accountId]);
    $status = $statusStmt->fetchColumn();

    if ($status !== 'active') {
        $pdo->rollBack();
        json_error('ACCOUNT_SUSPENDED', 'This account has been suspended.', 403);
    }

    $upsertDevice = $pdo->prepare(
        'INSERT INTO devices (account_id, device_id, device_name, platform, last_seen_at)
         VALUES (:account_id, :device_id, :device_name, :platform, NOW())
         ON DUPLICATE KEY UPDATE
            device_name = VALUES(device_name),
            platform = VALUES(platform),
            last_seen_at = NOW()'
    );
    $upsertDevice->execute([
        'account_id' => $accountId,
        'device_id' => $deviceId,
        'device_name' => $deviceName,
        'platform' => $platform,
    ]);

    // Mint a fresh bearer token on every login (rather than reusing an
    // existing one for this device) — simplest correct behavior, and it
    // means "log out this device" (a later phase) can always work by
    // revoking whatever token(s) exist for that device_id without needing
    // to reconcile with a client that might still be holding an old one.
    $rawToken = bin2hex(random_bytes(32));
    $tokenHash = hash('sha256', $rawToken);
    $expiresAt = date('Y-m-d H:i:s', time() + DEVICE_TOKEN_TTL_DAYS * 86400);

    $insertToken = $pdo->prepare(
        'INSERT INTO device_tokens (account_id, device_id, token_hash, expires_at)
         VALUES (:account_id, :device_id, :token_hash, :expires_at)'
    );
    $insertToken->execute([
        'account_id' => $accountId,
        'device_id' => $deviceId,
        'token_hash' => $tokenHash,
        'expires_at' => $expiresAt,
    ]);

    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    json_error('INTERNAL_ERROR', 'Something went wrong. Please try again.', 500);
}

$profilesStmt = $pdo->prepare(
    'SELECT profile_id, name, avatar, is_kids, created_at, updated_at
     FROM profiles
     WHERE account_id = :account_id AND deleted_at IS NULL
     ORDER BY created_at ASC'
);
$profilesStmt->execute(['account_id' => $accountId]);
$profiles = array_map(static function (array $row): array {
    return [
        'profile_id' => $row['profile_id'],
        'name' => $row['name'],
        'avatar' => $row['avatar'],
        'is_kids' => (bool) $row['is_kids'],
        'created_at' => $row['created_at'],
        'updated_at' => $row['updated_at'],
    ];
}, $profilesStmt->fetchAll());

json_success([
    'account_id' => $accountId,
    'device_token' => $rawToken,
    'expires_at' => $expiresAt,
    'profiles' => $profiles,
]);
