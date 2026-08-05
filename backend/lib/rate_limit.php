<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

/**
 * Returns the caller's IP address. Deliberately uses REMOTE_ADDR only, not
 * X-Forwarded-For — the latter is trivially spoofable by the client unless
 * you know for certain this sits behind a proxy/CDN that strips/overwrites
 * it, which a stock cPanel deployment does not. If this ever moves behind a
 * reverse proxy or CDN, this is the one place to update.
 */
function client_ip(): string
{
    return $_SERVER['REMOTE_ADDR'] ?? 'unknown';
}

/**
 * Fixed-window rate limiter backed by the `rate_limits` table (no Redis
 * available on shared cPanel hosting). The window boundary is baked into
 * $bucketKey itself via floor(time()/$windowSeconds), so a new window
 * automatically starts a fresh row once the current one "expires" — old rows
 * are simply never incremented again and can be pruned later by a cron job
 * (see README) without affecting correctness.
 *
 * Returns true if the call is within the allowed limit (and counts it),
 * false if the limit is already exceeded (caller should reject the request).
 */
function check_rate_limit(string $identifier, string $endpoint, int $maxRequests, int $windowSeconds): bool
{
    $windowIndex = (int) floor(time() / $windowSeconds);
    $bucketKey = hash('sha256', $identifier . ':' . $endpoint . ':' . $windowIndex);

    $pdo = db();
    $stmt = $pdo->prepare(
        'INSERT INTO rate_limits (bucket_key, request_count, window_start)
         VALUES (:bucket_key, 1, NOW())
         ON DUPLICATE KEY UPDATE request_count = request_count + 1'
    );
    $stmt->execute(['bucket_key' => $bucketKey]);

    $check = $pdo->prepare('SELECT request_count FROM rate_limits WHERE bucket_key = :bucket_key');
    $check->execute(['bucket_key' => $bucketKey]);
    $count = (int) $check->fetchColumn();

    return $count <= $maxRequests;
}
