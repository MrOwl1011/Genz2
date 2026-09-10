<?php
declare(strict_types=1);

/**
 * The server watcher, started by a cPanel cron command once a minute:
 *
 *     * * * * * /usr/local/bin/php /path/to/cron/monitor_servers.php
 *
 * For plans whose cron cannot run every minute, monitor/run.php does the same
 * job when an external cron site opens its link. The work itself lives in
 * lib/server_watch.php.
 *
 * Cron cannot fire more than once a minute, but watched servers can have
 * intervals down to 30 seconds, so this stays alive for about 50 seconds and
 * sweeps every 5. `--once` does a single sweep and exits — useful from cPanel's
 * terminal to see a check happen right away.
 */
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("This runs from cron, not from a browser. See monitor/run.php for a URL trigger.\n");
}

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../lib/server_watch.php';

const WATCH_RUN_SECONDS = 50;
const WATCH_POLL_SECONDS = 5;

$lock = watch_acquire_lock();
if ($lock === null) {
    exit(0); // A run is still going; it will pick up anything due.
}

$once = in_array('--once', $argv ?? [], true);
$pdo = db();
$deadline = microtime(true) + WATCH_RUN_SECONDS;

do {
    watch_heartbeat($pdo);
    watch_pass($pdo, $deadline);
    if ($once || microtime(true) + WATCH_POLL_SECONDS >= $deadline) {
        break;
    }
    sleep(WATCH_POLL_SECONDS);
} while (microtime(true) < $deadline);
