<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../../lib/xtream_client.php';

/**
 * Probes one monitored server and reports whether it answered.
 *
 * Takes an id, never a URL. The URL comes from monitored_servers, so this
 * endpoint cannot be pointed at an arbitrary address by whoever calls it —
 * it only ever reaches what an admin already saved. The SSRF guard still
 * runs on every probe (assert_safe_xtream_url, shared with login
 * validation), because DNS for a saved host can change after it was added.
 *
 * "Up" means the server returned any HTTP response. A 401, 403 or 404 is a
 * running server declining an anonymous request, which is exactly what an
 * Xtream panel does to a bare probe — reading those as "down" would mark
 * healthy panels red. Down is a connection failure, a timeout, or a 5xx
 * (including Cloudflare's 52x, which means the origin behind it is gone).
 */
require_admin_login();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'POST required.']);
    exit;
}
require_valid_csrf();

$id = (int) ($_POST['id'] ?? 0);
$stmt = db()->prepare('SELECT url FROM monitored_servers WHERE id = :id');
$stmt->execute(['id' => $id]);
$url = $stmt->fetchColumn();

if ($url === false) {
    http_response_code(404);
    echo json_encode(['success' => false, 'error' => 'That server is no longer listed.']);
    exit;
}

/** Emits a result and stops. */
function probe_result(bool $up, ?int $code, ?int $ms, ?string $error): never
{
    echo json_encode([
        'success' => true,
        'up' => $up,
        'code' => $code,
        'ms' => $ms,
        'error' => $error,
    ]);
    exit;
}

try {
    assert_safe_xtream_url((string) $url);
} catch (RuntimeException $e) {
    probe_result(false, null, null, $e->getMessage());
}

$ch = curl_init((string) $url);
curl_setopt_array($ch, [
    // HEAD: the headers are the whole answer, and a panel streaming a large
    // index page would otherwise make a status check slow.
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
// 8.5, where its notice printed into this JSON body and broke the page's
// parse — every probe then read as an error. The handle is freed when $ch
// goes out of scope.

if ($errno !== 0 || $code === 0) {
    $message = match ($errno) {
        // Either the 5s connect limit or the 8s total — the elapsed time
        // shown alongside says which.
        CURLE_OPERATION_TIMEDOUT => 'Timed out.',
        CURLE_COULDNT_CONNECT => 'Connection refused.',
        CURLE_COULDNT_RESOLVE_HOST => 'Host name does not resolve.',
        default => $error !== '' ? $error : 'No response.',
    };
    probe_result(false, null, $ms, $message);
}

probe_result($code < 500, $code, $ms, $code >= 500 ? "Server error $code." : null);
