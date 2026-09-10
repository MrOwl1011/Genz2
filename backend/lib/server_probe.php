<?php
declare(strict_types=1);

require_once __DIR__ . '/xtream_client.php';

/**
 * Checks whether one server answers, for both the live column on the admin
 * Servers page and the cron watcher, so the two can never disagree about what
 * "up" means.
 *
 * "Up" is any HTTP response. A 401, 403 or 404 is a running panel declining
 * an anonymous request, which is what an Xtream panel does to a bare probe —
 * reading those as down would paint healthy panels red. Down is a connection
 * failure, a timeout, or a 5xx (including Cloudflare's 52x, meaning the
 * origin behind it is gone).
 *
 * The SSRF guard runs on every probe, not only when a URL is saved, because
 * DNS for a saved host can change afterwards.
 *
 * @return array{up: bool, code: ?int, ms: ?int, error: ?string}
 */
function probe_server(string $url): array
{
    try {
        assert_safe_xtream_url($url);
    } catch (RuntimeException $e) {
        return ['up' => false, 'code' => null, 'ms' => null, 'error' => $e->getMessage()];
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        // HEAD: the headers are the whole answer, and a panel serving a large
        // index page would otherwise make every check slow.
        CURLOPT_NOBODY => true,
        CURLOPT_RETURNTRANSFER => true,
        // A redirect is itself a response, so it counts as up; following it
        // would also let a saved host bounce the probe somewhere unchecked.
        CURLOPT_FOLLOWLOCATION => false,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT => 8,
        CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
        // Reachability, not trust. Nothing secret is sent, and plenty of IPTV
        // panels run expired or self-signed certificates — verifying would
        // report a live server as down.
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_SSL_VERIFYHOST => 0,
        CURLOPT_USERAGENT => 'GENz+ status check',
    ]);

    $started = microtime(true);
    curl_exec($ch);
    $ms = (int) round((microtime(true) - $started) * 1000);
    $code = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $errno = curl_errno($ch);
    $error = curl_error($ch);
    // No curl_close(): it has done nothing since PHP 8.0 and is deprecated in
    // 8.5, where its notice printed into the JSON the admin page parses. The
    // handle is freed when $ch goes out of scope.

    if ($errno !== 0 || $code === 0) {
        $message = match ($errno) {
            // Either the 5s connect limit or the 8s total — the elapsed time
            // reported alongside says which.
            CURLE_OPERATION_TIMEDOUT => 'Timed out.',
            CURLE_COULDNT_CONNECT => 'Connection refused.',
            CURLE_COULDNT_RESOLVE_HOST => 'Host name does not resolve.',
            default => $error !== '' ? $error : 'No response.',
        };
        return ['up' => false, 'code' => null, 'ms' => $ms, 'error' => $message];
    }

    return [
        'up' => $code < 500,
        'code' => $code,
        'ms' => $ms,
        'error' => $code >= 500 ? "Server error $code." : null,
    ];
}
