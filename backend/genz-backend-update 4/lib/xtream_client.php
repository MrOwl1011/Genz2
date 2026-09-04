<?php
declare(strict_types=1);

require_once __DIR__ . '/../config.php';

/**
 * Builds the actual player_api.php URL to call, mirroring the normalization
 * lib/services/xtream_api_service.dart's normalizeUrl() already does
 * client-side (add http:// if no scheme given, strip trailing slash, ensure
 * /player_api.php suffix). This is a *different* normalization from
 * account_id.php's normalize_server_url() — that one is for identity, this
 * one is for actually reaching the panel.
 */
function build_xtream_api_url(string $serverUrl): string
{
    $url = trim($serverUrl);
    if (!preg_match('#^https?://#i', $url)) {
        $url = 'http://' . $url;
    }
    $url = rtrim($url, '/');
    if (!preg_match('#/player_api\.php$#i', $url)) {
        $url .= '/player_api.php';
    }
    return $url;
}

/**
 * Rejects a single IP address unless it's a routable public address. Wraps
 * PHP's own FILTER_VALIDATE_IP flags, which cover both IPv4 and IPv6
 * loopback/private/link-local/reserved ranges in one call — deliberately not
 * hand-rolling CIDR checks here.
 */
function assert_public_ip(string $ip): void
{
    $valid = filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE);
    if ($valid === false) {
        throw new RuntimeException('Server URL points to a disallowed address.');
    }
}

/**
 * SSRF guard: this backend makes an outbound HTTP request to a URL the
 * caller supplies, so it must not be usable to reach internal/loopback
 * network addresses (e.g. "http://127.0.0.1/admin", "http://localhost:3306",
 * an internal-only hostname, etc.).
 *
 * Known residual limitation, acceptable for this phase: there is a small
 * window between this DNS check and curl's own (separate) DNS resolution
 * during the actual request, so a malicious DNS server could theoretically
 * answer differently between the two lookups ("DNS rebinding"). Closing that
 * gap fully requires resolving once and pinning curl to the resolved IP
 * (CURLOPT_RESOLVE) — left for the hardening phase rather than done here.
 */
function assert_safe_xtream_url(string $url): void
{
    $parts = parse_url($url);
    if ($parts === false || !isset($parts['scheme'], $parts['host'])) {
        throw new RuntimeException('Invalid Server URL.');
    }

    $scheme = strtolower($parts['scheme']);
    if ($scheme !== 'http' && $scheme !== 'https') {
        throw new RuntimeException('Server URL must use http or https.');
    }

    $host = $parts['host'];

    if (filter_var($host, FILTER_VALIDATE_IP)) {
        assert_public_ip($host);
        return;
    }

    $records = @dns_get_record($host, DNS_A + DNS_AAAA);
    if ($records === false || count($records) === 0) {
        throw new RuntimeException('Could not resolve the Server URL.');
    }

    foreach ($records as $record) {
        $ip = $record['ip'] ?? ($record['ipv6'] ?? null);
        if ($ip !== null) {
            assert_public_ip($ip);
        }
    }
}

/**
 * Independently re-validates Xtream credentials by calling the user's own
 * panel directly — mirrors XtreamApiService.authenticate()'s auth check
 * (user_info.auth must be truthy) but from the server, not trusting any
 * claim the Flutter client makes. This is the fix for the "anyone who
 * derives/guesses a valid account_id could read someone else's data" gap:
 * account_id alone is never sufficient to get past login.php — a real,
 * currently-valid password against the real panel is required every time.
 *
 * Throws RuntimeException with a user-facing message on any failure
 * (unreachable server, bad response shape, or rejected credentials).
 * Returns the panel's `user_info` object on success.
 */
function validate_xtream_login(string $serverUrl, string $username, string $password): array
{
    $apiUrl = build_xtream_api_url($serverUrl);
    assert_safe_xtream_url($apiUrl);

    $requestUrl = $apiUrl . '?' . http_build_query([
        'username' => $username,
        'password' => $password,
    ]);

    $ch = curl_init($requestUrl);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => false, // never auto-follow redirects — reject instead (see assert_safe_xtream_url doc)
        CURLOPT_TIMEOUT => XTREAM_VALIDATION_TIMEOUT_SECONDS,
        CURLOPT_CONNECTTIMEOUT => XTREAM_VALIDATION_TIMEOUT_SECONDS,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
    ]);

    $body = curl_exec($ch);
    $curlErrno = curl_errno($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($curlErrno !== 0) {
        throw new RuntimeException('Could not reach the IPTV server. Please check the Server URL and try again.');
    }

    if ($httpCode < 200 || $httpCode >= 300) {
        throw new RuntimeException('The IPTV server returned an unexpected response (HTTP ' . $httpCode . ').');
    }

    $data = json_decode((string) $body, true);
    if (!is_array($data) || !isset($data['user_info']) || !is_array($data['user_info'])) {
        throw new RuntimeException('The IPTV server returned an invalid response.');
    }

    $userInfo = $data['user_info'];
    $auth = $userInfo['auth'] ?? null;
    $authOk = $auth === 1 || $auth === '1' || $auth === true;
    if (!$authOk) {
        $message = (isset($userInfo['message']) && is_string($userInfo['message']) && $userInfo['message'] !== '')
            ? $userInfo['message']
            : 'Invalid username or password.';
        throw new RuntimeException($message);
    }

    return $userInfo;
}
