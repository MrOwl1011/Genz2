<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/pairing.php';
require_once __DIR__ . '/../../lib/db.php';

/**
 * Moves the calling device from its current account onto the account a
 * pairing code was issued for — for a device that already registered
 * (register.php, with no code) and only afterwards got a code from another
 * device to join. register.php's own pairing_code parameter covers the more
 * common case (entering a code before the very first registration); this
 * covers "I already opened the app once, and only now got the code."
 *
 * This moves the *device*, not its data: any profiles/favorites/history
 * already written under the old account_id stay there and are not merged
 * in. In practice that is essentially always empty — a device that has not
 * yet joined anyone's sync group has nothing of its own to bring — so this
 * is deliberately kept simple rather than replicating migrate_legacy.php's
 * merge logic for a case that does not arise in normal use.
 */
require_api_key();
$auth = require_device_token();

$body = read_json_body();
$code = isset($body['code']) ? trim((string) $body['code']) : '';

if ($code === '') {
    json_error('INVALID_BODY', 'code is required.', 400);
}

$targetAccountId = resolve_pairing_code($code);
if ($targetAccountId === null) {
    json_error('INVALID_CODE', 'This code is invalid or has expired.', 404);
}

if ($targetAccountId === $auth['account_id']) {
    json_error('ALREADY_JOINED', 'This device is already on that account.', 409);
}

$pdo = db();
$pdo->beginTransaction();

try {
    $statusStmt = $pdo->prepare('SELECT status FROM accounts WHERE account_id = :account_id');
    $statusStmt->execute(['account_id' => $targetAccountId]);
    $status = $statusStmt->fetchColumn();
    if ($status !== 'active') {
        $pdo->rollBack();
        json_error('ACCOUNT_SUSPENDED', 'This account has been suspended.', 403);
    }

    // This device_id may already have a row under the target account from a
    // previous life (e.g. it joined, left, and is rejoining) — repoint
    // rather than insert, exactly as register.php's ON DUPLICATE KEY UPDATE
    // does for a fresh registration.
    $upsertDevice = $pdo->prepare(
        'INSERT INTO devices (account_id, device_id, device_name, platform, last_seen_at)
         SELECT :target_account_id, device_id, device_name, platform, NOW()
         FROM devices WHERE account_id = :old_account_id AND device_id = :device_id
         ON DUPLICATE KEY UPDATE last_seen_at = NOW()'
    );
    $upsertDevice->execute([
        'target_account_id' => $targetAccountId,
        'old_account_id' => $auth['account_id'],
        'device_id' => $auth['device_id'],
    ]);

    $deleteOldDevice = $pdo->prepare(
        'DELETE FROM devices WHERE account_id = :account_id AND device_id = :device_id'
    );
    $deleteOldDevice->execute([
        'account_id' => $auth['account_id'],
        'device_id' => $auth['device_id'],
    ]);

    // Revoke every token this device held on the old account and mint a
    // fresh one on the new account, rather than repointing the existing
    // token row — the client is about to receive a brand-new token anyway,
    // and leaving stale ones around revoked is simpler to reason about than
    // trying to update a row the client already has a copy of.
    $revokeOld = $pdo->prepare(
        'UPDATE device_tokens SET revoked_at = NOW()
         WHERE account_id = :account_id AND device_id = :device_id AND revoked_at IS NULL'
    );
    $revokeOld->execute([
        'account_id' => $auth['account_id'],
        'device_id' => $auth['device_id'],
    ]);

    $rawToken = bin2hex(random_bytes(32));
    $tokenHash = hash('sha256', $rawToken);
    $expiresAt = date('Y-m-d H:i:s', time() + DEVICE_TOKEN_TTL_DAYS * 86400);

    $insertToken = $pdo->prepare(
        'INSERT INTO device_tokens (account_id, device_id, token_hash, expires_at)
         VALUES (:account_id, :device_id, :token_hash, :expires_at)'
    );
    $insertToken->execute([
        'account_id' => $targetAccountId,
        'device_id' => $auth['device_id'],
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
$profilesStmt->execute(['account_id' => $targetAccountId]);
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
    'account_id' => $targetAccountId,
    'device_token' => $rawToken,
    'expires_at' => $expiresAt,
    'profiles' => $profiles,
]);
