<?php
declare(strict_types=1);

/**
 * account_id = SHA256(normalize(server_url) + normalize(username)).
 *
 * CRITICAL: this formula must stay byte-for-byte identical to whatever gets
 * added to lib/providers/auth_provider.dart in a later phase (an
 * `accountId` getter alongside the existing `playlistId` one). If the two
 * ever drift, the same Xtream account will compute a different account_id on
 * the client vs. the server and silently fail to match up. Do not "improve"
 * this normalization independently on one side without updating the other.
 *
 * normalize = lowercase + trim + strip a single trailing slash. Deliberately
 * does NOT touch scheme (http/https) or path — e.g. does not strip
 * "/player_api.php" the way the existing XtreamApiService.normalizeUrl()
 * does for building request URLs; that's a different, unrelated
 * normalization used only for talking to the Xtream panel, not for identity.
 */
function normalize_server_url(string $serverUrl): string
{
    $normalized = strtolower(trim($serverUrl));
    return rtrim($normalized, '/');
}

function normalize_username(string $username): string
{
    return strtolower(trim($username));
}

function compute_account_id(string $serverUrl, string $username): string
{
    return hash('sha256', normalize_server_url($serverUrl) . normalize_username($username));
}

/**
 * account_id for every account created from here on. Deliberately unrelated
 * to any Xtream credential — see register.php's doc comment for why this
 * replaced compute_account_id() as the identity for new accounts.
 * compute_account_id() itself is kept only for migrate_legacy.php, which
 * needs to look up accounts that were created under the old scheme before
 * this change.
 *
 * 32 random bytes hex-encoded to 64 chars, matching accounts.account_id's
 * existing CHAR(64) column exactly — no schema change needed to switch
 * schemes.
 */
function generate_anonymous_account_id(): string
{
    return bin2hex(random_bytes(32));
}
