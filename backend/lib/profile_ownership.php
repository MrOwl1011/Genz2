<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/json_response.php';

/**
 * Every favorites/history endpoint takes a profile_id in its body and must
 * confirm it actually belongs to the authenticated account (resolved from
 * the bearer token, never trusted from the request) before touching any
 * data under it — otherwise account A could read/write account B's data by
 * simply guessing/reusing a profile_id. Terminates the request with 404 on
 * failure (not 403 — doesn't confirm to the caller whether the profile_id
 * exists at all under a different account).
 */
function assert_profile_owned_by_account(string $profileId, string $accountId): void
{
    $stmt = db()->prepare(
        'SELECT 1 FROM profiles WHERE profile_id = :profile_id AND account_id = :account_id AND deleted_at IS NULL'
    );
    $stmt->execute(['profile_id' => $profileId, 'account_id' => $accountId]);
    if ($stmt->fetchColumn() === false) {
        json_error('PROFILE_NOT_FOUND', 'Profile not found.', 404);
    }
}
