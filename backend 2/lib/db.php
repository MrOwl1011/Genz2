<?php
declare(strict_types=1);

require_once __DIR__ . '/../config.php';

/**
 * Returns a shared PDO connection, created on first use. PDO singleton, not a
 * connection-per-request pool — a single request only ever needs one
 * connection on this stack (no persistent workers to pool across).
 */
function db(): PDO
{
    static $pdo = null;
    if ($pdo !== null) {
        return $pdo;
    }

    // PDO::ATTR_EMULATE_PREPARES = false means *native* prepared statements
    // (MySQL's real binary protocol, not PHP faking it client-side). Real
    // consequence to know before writing a query anywhere in this codebase:
    // the same named placeholder (e.g. :id) cannot appear more than once in
    // a single query — bind a second, distinctly-named placeholder to the
    // same value instead. This bit two dynamically-built queries in admin/
    // during review (search WHERE clauses built from string fragments,
    // where the duplication wasn't visible as a literal string in any one
    // place) — worth double-checking any new query built from concatenated/
    // interpolated fragments rather than typed out as one literal string.
    $dsn = 'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4';
    $pdo = new PDO($dsn, DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);

    return $pdo;
}
