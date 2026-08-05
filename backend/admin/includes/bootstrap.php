<?php
declare(strict_types=1);

require_once __DIR__ . '/../../config.php';
require_once __DIR__ . '/../../lib/db.php';

// Admin auth is a deliberately separate scheme from the app's device-token
// bearer auth (see backend/lib/auth_guard.php) — plain PHP sessions, meant
// to be used by a human in a browser, not the Flutter app.
session_start();

const ADMIN_SESSION_IDLE_TIMEOUT_SECONDS = 3600; // 1 hour

function html_escape(?string $value): string
{
    return htmlspecialchars($value ?? '', ENT_QUOTES, 'UTF-8');
}

function is_admin_logged_in(): bool
{
    if (!isset($_SESSION['admin_id'], $_SESSION['admin_last_activity'])) {
        return false;
    }
    if (time() - (int) $_SESSION['admin_last_activity'] > ADMIN_SESSION_IDLE_TIMEOUT_SECONDS) {
        session_unset();
        session_destroy();
        return false;
    }
    $_SESSION['admin_last_activity'] = time();
    return true;
}

/** Redirects to login.php if not authenticated. Call at the top of every admin page except login.php/setup.php. */
function require_admin_login(): void
{
    if (!is_admin_logged_in()) {
        header('Location: login.php');
        exit;
    }
}

function csrf_token(): string
{
    if (empty($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

/** Call at the top of every POST handler. Terminates the request on mismatch. */
function require_valid_csrf(): void
{
    $submitted = $_POST['csrf_token'] ?? '';
    $expected = $_SESSION['csrf_token'] ?? '';
    if ($expected === '' || !hash_equals($expected, (string) $submitted)) {
        http_response_code(403);
        exit('Invalid or expired form submission. Please go back and try again.');
    }
}
