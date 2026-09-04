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

/**
 * Every DATETIME column in this database is stored in UTC with no
 * timezone marker (see core/datetime_utils.dart's matching note on the
 * Flutter side) — MySQL's NOW() and PHP's date functions on this server
 * are not assumed to agree on what timezone that is, so this always
 * treats the raw value as UTC explicitly rather than relying on the
 * server's default timezone, then converts to a fixed GMT+3 for display.
 * Fixed offset rather than a named zone (e.g. Asia/Kuwait) — none of the
 * GMT+3 countries this admin panel is used from observe DST, so there's
 * no correctness reason to depend on the server's tzdata being current.
 */
function admin_display_time(?string $utcDatetime): string
{
    if ($utcDatetime === null || $utcDatetime === '') {
        return 'Never';
    }
    try {
        $dt = new DateTime($utcDatetime, new DateTimeZone('UTC'));
        $dt->setTimezone(new DateTimeZone('+03:00'));
        return $dt->format('Y-m-d H:i');
    } catch (Exception $e) {
        return $utcDatetime;
    }
}

/**
 * Every account this panel displays used to have a username/server_url —
 * that's no longer true (see lib/account_id.php's
 * generate_anonymous_account_id() doc comment): new accounts store neither,
 * by design, since this backend no longer learns a user's Xtream identity at
 * all. A handful of legacy rows may still carry the old
 * username/server_url until migrate_legacy.php folds them into an anonymous
 * account the first time that user's device re-registers — those still
 * display exactly as before. For everyone else there's nothing
 * credential-derived left to show, so this falls back to the most
 * recently-seen device's name (pass it as $latestDeviceName from a query
 * that LEFT JOINs devices — see accounts.php/index.php), and finally to a
 * shortened account_id if even that's unavailable (an account with zero
 * devices, e.g. one created via a pairing code that's never actually been
 * used to register a second device yet).
 */
function account_label(?string $username, string $accountId, ?string $latestDeviceName = null): string
{
    if ($username !== null && $username !== '') {
        return $username;
    }
    if ($latestDeviceName !== null && $latestDeviceName !== '') {
        return $latestDeviceName;
    }
    return substr($accountId, 0, 12) . '…';
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
