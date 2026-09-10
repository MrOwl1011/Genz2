<?php
declare(strict_types=1);

/**
 * The server watcher, started by opening a URL rather than by a cPanel cron
 * command — for hosting plans whose cron cannot run every minute, using an
 * external cron site such as cron-job.org on a 5-minute schedule instead.
 *
 * Protected by a long random key created on the admin Servers page. With no
 * key saved it refuses every request, so the checker cannot be triggered by
 * anyone until an admin creates the link. Knowing the link only makes the
 * checker run; it returns nothing about the servers.
 *
 * One sweep, finished well inside the ~30 seconds most cron sites wait. It
 * stops starting new probes after 12 seconds, and the slowest single probe — a
 * dead server: 5 seconds, a 3-second pause, 5 again — takes about 13, so a
 * call ends by roughly 25 seconds. Any server not reached stays due and is
 * checked on the next call.
 */
require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../lib/server_watch.php';

const RUN_START_BUDGET_SECONDS = 12;
const RUN_MIN_SPACING_SECONDS = 20;

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');
header('X-Robots-Tag: noindex');

function run_reply(int $status, string $text): never
{
    http_response_code($status);
    echo $text, "\n";
    exit;
}

try {
    $saved = settings_get(['monitor_token'])['monitor_token'];
} catch (PDOException $e) {
    // app_settings is created by migration_004. Say so, rather than 500 — a
    // cron site only shows the status code, and a bare 500 explains nothing.
    run_reply(503, 'Database update needed: run sql/migration_004_server_monitoring.sql in phpMyAdmin.');
}
if ($saved === '') {
    run_reply(403, 'No checker link has been created yet. Create one on the admin Servers page.');
}
if (!hash_equals($saved, (string) ($_GET['key'] ?? ''))) {
    run_reply(403, 'Wrong key.');
}

$pdo = db();

// Every call makes outbound requests, so a burst of calls on this link must
// not become a burst of probes. 200 rather than an error: to a cron site an
// error looks like a broken job, and some disable a job after repeated ones.
$age = $pdo->query(
    "SELECT TIMESTAMPDIFF(SECOND, value, NOW()) FROM app_settings WHERE name = 'monitor_last_run'"
)->fetchColumn();
if ($age !== false && $age !== null && (int) $age < RUN_MIN_SPACING_SECONDS) {
    run_reply(200, 'OK: skipped, the checker ran ' . (int) $age . ' seconds ago.');
}

$lock = watch_acquire_lock();
if ($lock === null) {
    run_reply(200, 'OK: a check is already running.');
}

// Finish the sweep even if the cron site stops waiting for the reply.
ignore_user_abort(true);
set_time_limit(60);

$started = microtime(true);
try {
    watch_heartbeat($pdo);
    $tally = watch_pass($pdo, $started + RUN_START_BUDGET_SECONDS);
} catch (Throwable $e) {
    // Detail to the server's error log, not to whoever holds the link.
    error_log('[monitor/run.php] ' . $e->getMessage());
    run_reply(500, 'The check failed. The details are in the server error log.');
}

run_reply(200, sprintf(
    'OK: checked %d, left for next run %d, alerts %d, took %.1fs.',
    $tally['checked'],
    $tally['deferred'],
    $tally['alerts'],
    microtime(true) - $started
));
