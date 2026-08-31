<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/json_response.php';

/**
 * Validates the `Authorization: Bearer <token>` header against
 * `device_tokens` and returns the account_id/device_id it resolves to.
 * Client-supplied account_id/device_id in the request body is never trusted
 * for authorization anywhere in this API — every endpoint from Phase 1
 * onward calls this first and uses only what it returns.
 *
 * Not used by anything yet in Phase 0 (login.php is what *creates* tokens,
 * it doesn't require one) — built now so later phases' endpoints don't need
 * to revisit login.php or invent their own auth resolution.
 *
 * Terminates the request with a 401 on any failure; otherwise returns
 * ['account_id' => string, 'device_id' => string].
 */
function require_device_token(): array
{
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';

    // A handful of common PHP/Apache setups (including some cPanel/mod_php
    // configurations) strip the Authorization header from $_SERVER by
    // default unless explicitly passed through — fall back to the usual
    // alternate places it surfaces instead of failing every request on
    // hosts configured that way.
    if ($header === '' && isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
        $header = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    }
    if ($header === '' && function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        $header = $headers['Authorization'] ?? ($headers['authorization'] ?? '');
    }

    if (!preg_match('/^Bearer\s+(.+)$/i', $header, $matches)) {
        json_error('UNAUTHORIZED', 'Missing or invalid Authorization header.', 401);
    }

    $token = trim($matches[1]);
    $tokenHash = hash('sha256', $token);

    $pdo = db();
    $stmt = $pdo->prepare(
        'SELECT account_id, device_id, expires_at, revoked_at
         FROM device_tokens WHERE token_hash = :token_hash'
    );
    $stmt->execute(['token_hash' => $tokenHash]);
    $row = $stmt->fetch();

    if ($row === false) {
        json_error('UNAUTHORIZED', 'Invalid session. Please log in again.', 401);
    }

    if ($row['revoked_at'] !== null) {
        json_error('UNAUTHORIZED', 'This device has been logged out. Please log in again.', 401);
    }

    if (strtotime((string) $row['expires_at']) < time()) {
        json_error('UNAUTHORIZED', 'Session expired. Please log in again.', 401);
    }

    return [
        'account_id' => $row['account_id'],
        'device_id' => $row['device_id'],
    ];
}
