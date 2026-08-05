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
