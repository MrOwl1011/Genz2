<?php
declare(strict_types=1);

require_once __DIR__ . '/../../lib/json_response.php';
require_once __DIR__ . '/../../lib/api_key_guard.php';
require_once __DIR__ . '/../../lib/auth_guard.php';
require_once __DIR__ . '/../../lib/account_id.php';
require_once __DIR__ . '/../../lib/db.php';

/**
 * One-time bridge from the old scheme (account_id = SHA256(server_url +
 * username), created by the now-removed login.php) to a caller's new
 * anonymous account. Folds every profile/device/token that existed under
 * the legacy account into the caller's account_id, then deletes the empty
 * legacy row.
 *
 * The client sends server_url + username the same way the old login.php
 * once required — but only ever this once, to locate data that already
 * exists under the old identity, never stored again. This endpoint
 * recomputes the legacy hash itself rather than trusting a client-supplied
 * one, for the same reason register.php never trusted client-supplied
 * account_ids: knowledge of a still-valid device_token for the NEW account
 * (required to call this at all) plus the exact server_url/username is
 * treated as sufficient proof, matching exactly what the original login.php
 * required to establish that identity in the first place.
 */
require_api_key();
$auth = require_device_token();

$body = read_json_body();
$serverUrl = isset($body['server_url']) ? (string) $body['server_url'] : '';
$username = isset($body['username']) ? (string) $body['username'] : '';

if ($serverUrl === '' || $username === '') {
    json_error('INVALID_BODY', 'server_url and username are required.', 400);
}

$legacyAccountId = compute_account_id($serverUrl, $username);
$newAccountId = $auth['account_id'];

if ($legacyAccountId === $newAccountId) {
    // Only possible if account_id generation ever collided with a legacy
    // hash — astronomically unlikely, but "nothing to migrate" is the
    // correct response either way.
    json_success(['migrated' => false]);
}

$pdo = db();
$pdo->beginTransaction();

try {
    $legacyStmt = $pdo->prepare('SELECT account_id FROM accounts WHERE account_id = :account_id FOR UPDATE');
    $legacyStmt->execute(['account_id' => $legacyAccountId]);
    if ($legacyStmt->fetchColumn() === false) {
        // No legacy account under these credentials — most callers hit this
        // path (anyone who only ever installed after this change), and it
        // is not an error.
        $pdo->commit();
        json_success(['migrated' => false]);
    }

    // The device calling this already has rows under the new account from
    // register.php. If this exact device previously used the legacy
    // account too, moving the legacy row would collide with those — drop
    // the brand-new, still-empty rows first so the legacy ones (which may
    // carry real last_seen_at history) win.
    $dropNewDevice = $pdo->prepare(
        'DELETE FROM devices WHERE account_id = :account_id AND device_id = :device_id'
    );
    $dropNewDevice->execute(['account_id' => $newAccountId, 'device_id' => $auth['device_id']]);

    $moveDevices = $pdo->prepare(
        'UPDATE devices SET account_id = :new_account_id WHERE account_id = :legacy_account_id'
    );
    $moveDevices->execute(['new_account_id' => $newAccountId, 'legacy_account_id' => $legacyAccountId]);

    $moveTokens = $pdo->prepare(
        'UPDATE device_tokens SET account_id = :new_account_id WHERE account_id = :legacy_account_id'
    );
    $moveTokens->execute(['new_account_id' => $newAccountId, 'legacy_account_id' => $legacyAccountId]);

    $moveProfiles = $pdo->prepare(
        'UPDATE profiles SET account_id = :new_account_id WHERE account_id = :legacy_account_id'
    );
    $moveProfiles->execute(['new_account_id' => $newAccountId, 'legacy_account_id' => $legacyAccountId]);

    $deleteLegacyAccount = $pdo->prepare('DELETE FROM accounts WHERE account_id = :account_id');
    $deleteLegacyAccount->execute(['account_id' => $legacyAccountId]);

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
$profilesStmt->execute(['account_id' => $newAccountId]);
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

json_success(['migrated' => true, 'profiles' => $profiles]);
