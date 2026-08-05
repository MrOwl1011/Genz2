<?php
// Phase 0 backend configuration — fill in the placeholders below after
// creating the database via cPanel's "MySQL Database Wizard" (see README.md).
//
// This file is deliberately kept as plain PHP constants (no .env parser
// dependency) since this runs on stock shared cPanel hosting with no
// Composer/build step assumed.

declare(strict_types=1);

// ─── Database ───────────────────────────────────────────────────────────────
// cPanel MySQL host is almost always "localhost". cPanel-created DB/user names
// are typically prefixed with your cPanel account name, e.g. "cpaneluser_genz".
define('DB_HOST', 'localhost');
define('DB_NAME', 'CHANGEME_database_name');
define('DB_USER', 'CHANGEME_database_user');
define('DB_PASS', 'CHANGEME_database_password');

// ─── API key (static, checked on every request including login) ────────────
// Generate a real value with: php -r "echo bin2hex(random_bytes(32));"
// This is NOT per-account auth (see device tokens below) — it just gates the
// whole API against casual scanning/abuse, since login.php triggers an
// outbound HTTP request to a caller-supplied Xtream server URL.
define('API_KEY', 'CHANGEME_generate_a_long_random_string');

// ─── Device bearer tokens (issued per successful login) ─────────────────────
// Only the SHA-256 hash of the raw token is ever stored (see device_tokens
// table) — this only controls how long a token stays valid before the app
// must log in again.
define('DEVICE_TOKEN_TTL_DAYS', 90);

// ─── Rate limiting ───────────────────────────────────────────────────────────
define('LOGIN_RATE_LIMIT_MAX', 10);       // max login attempts...
define('LOGIN_RATE_LIMIT_WINDOW', 3600);  // ...per this many seconds, per IP.
define('WRITE_RATE_LIMIT_MAX', 120);      // max profile/favorite/history writes...
define('WRITE_RATE_LIMIT_WINDOW', 60);    // ...per this many seconds, per device token.

// ─── Profiles ────────────────────────────────────────────────────────────────
define('MAX_PROFILES_PER_ACCOUNT', 5);

// ─── Xtream re-validation call ───────────────────────────────────────────────
define('XTREAM_VALIDATION_TIMEOUT_SECONDS', 12);

// ─── Environment ─────────────────────────────────────────────────────────────
// Set to false once deployed to production — true only helps while you're
// still wiring up config.php locally/on a staging subdomain.
define('DEBUG_MODE', false);

if (DEBUG_MODE) {
    ini_set('display_errors', '1');
    error_reporting(E_ALL);
} else {
    ini_set('display_errors', '0');
    error_reporting(E_ALL);
}
