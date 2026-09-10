<?php
declare(strict_types=1);

/**
 * Background watcher for the admin Servers page.
 *
 * Run by cron once a minute:
 *
 *     * * * * * /usr/local/bin/php /path/to/cron/monitor_servers.php
 *
 * Cron cannot fire more often than once a minute, but watched servers can
 * have intervals down to 30 seconds. Each run therefore stays alive for about
 * 50 seconds and looks for due servers every 5, which gives the intervals real
 * meaning. A lock stops a slow run from overlapping the next one.
 *
 * Emails go out only when a server's state changes: one when it goes down, one
 * when it comes back. Alerting on every check would send one email every 30
 * seconds for as long as a panel is down. A failed check is repeated once
 * after a short pause before it counts, so a single dropped connection does
 * not page anyone.
 *
 * `--once` does a single pass and exits, instead of staying alive for the
 * minute. Useful from cPanel's terminal to see a check happen right away.
 */
if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("This runs from cron, not from a browser.\n");
}

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../lib/db.php';
require_once __DIR__ . '/../lib/app_settings.php';
require_once __DIR__ . '/../lib/server_probe.php';
require_once __DIR__ . '/../lib/smtp_mailer.php';

const WATCH_RUN_SECONDS = 50;
const WATCH_POLL_SECONDS = 5;
const WATCH_RETRY_DELAY_SECONDS = 3;

$lock = fopen(sys_get_temp_dir() . '/genz_monitor_' . md5(__DIR__) . '.lock', 'c');
if ($lock === false || !flock($lock, LOCK_EX | LOCK_NB)) {
    exit(0); // The previous run is still going; it will pick up anything due.
}

$once = in_array('--once', $argv ?? [], true);
$pdo = db();
$deadline = time() + WATCH_RUN_SECONDS;

// Written through NOW() rather than from PHP, so the admin page can compare
// it with NOW() and the database's own timezone cancels out.
$heartbeat = $pdo->prepare(
    "INSERT INTO app_settings (name, value) VALUES ('monitor_last_run', NOW())
     ON DUPLICATE KEY UPDATE value = NOW()"
);
$claim = $pdo->prepare(
    'UPDATE server_monitors SET next_check_at = NOW() + INTERVAL :seconds SECOND
     WHERE server_id = :id'
);
$record = $pdo->prepare(
    'UPDATE server_monitors
        SET last_up = :up, last_code = :code, last_ms = :ms, last_error = :error,
            last_checked_at = NOW(),
            status_since = IF(:changed = 1, NOW(), status_since)
      WHERE server_id = :id'
);

do {
    $heartbeat->execute();

    $due = $pdo->query(
        'SELECT m.server_id, m.interval_seconds, m.last_up,
                TIMESTAMPDIFF(SECOND, m.status_since, NOW()) AS state_seconds,
                s.label, s.url
           FROM server_monitors m
           JOIN monitored_servers s ON s.id = m.server_id
          WHERE m.enabled = 1
            AND (m.next_check_at IS NULL OR m.next_check_at <= NOW())
          ORDER BY m.next_check_at'
    )->fetchAll();

    foreach ($due as $row) {
        // Claim first: a slow probe must not leave the server looking due to
        // the next poll and get checked twice.
        $claim->execute(['seconds' => (int) $row['interval_seconds'], 'id' => $row['server_id']]);

        $result = probe_server((string) $row['url']);
        if (!$result['up']) {
            sleep(WATCH_RETRY_DELAY_SECONDS);
            $result = probe_server((string) $row['url']);
        }

        $wasUp = $row['last_up'] === null ? null : ((int) $row['last_up'] === 1);
        // First observation of a server counts as a change: it starts the
        // "since" clock, and if the server is already down, that is worth an
        // email.
        $changed = $wasUp === null || $wasUp !== $result['up'];

        $record->execute([
            'up' => $result['up'] ? 1 : 0,
            'code' => $result['code'],
            'ms' => $result['ms'],
            'error' => $result['error'] === null ? null : mb_substr($result['error'], 0, 255),
            'changed' => $changed ? 1 : 0,
            'id' => $row['server_id'],
        ]);

        // No email for a server first seen healthy — nothing happened.
        if ($changed && !($wasUp === null && $result['up'])) {
            watch_send_alert($row, $result, $wasUp === false ? (int) $row['state_seconds'] : null);
        }
    }

    if ($once || time() + WATCH_POLL_SECONDS >= $deadline) {
        break;
    }
    sleep(WATCH_POLL_SECONDS);
} while (time() < $deadline);

/**
 * Emails one state change. A failure is stored for the Servers page to show
 * rather than thrown: one broken mailbox must not stop the rest of the checks.
 */
function watch_send_alert(array $row, array $result, ?int $downSeconds): void
{
    $name = trim((string) $row['label']) !== ''
        ? (string) $row['label']
        : (string) (parse_url((string) $row['url'], PHP_URL_HOST) ?: $row['url']);
    $when = (new DateTime('now', new DateTimeZone('+03:00')))->format('Y-m-d H:i') . ' (GMT+3)';

    if ($result['up']) {
        $subject = "[GENz+] Back up: $name";
        $body = "$name is back up.\n\n"
            . "URL:        {$row['url']}\n"
            . "Response:   HTTP {$result['code']} in {$result['ms']} ms\n"
            . ($downSeconds !== null ? 'Down for:   ' . watch_duration($downSeconds) . "\n" : '')
            . "Checked:    $when\n";
    } else {
        $subject = "[GENz+] DOWN: $name";
        $body = "$name is not responding.\n\n"
            . "URL:        {$row['url']}\n"
            . 'Reason:     ' . ($result['error'] ?? 'No response.') . "\n"
            . "Checked:    $when (confirmed by a second check)\n";
    }
    $body .= "\nGENz+ server monitor. This server is checked every "
        . (int) $row['interval_seconds'] . " seconds; you get one email when it goes down\n"
        . "and one when it comes back.\n";

    try {
        smtp_send(smtp_load_config(), $subject, $body);
        settings_set(['monitor_mail_error' => '']);
    } catch (RuntimeException $e) {
        settings_set(['monitor_mail_error' => $e->getMessage()]);
    }
}

function watch_duration(int $seconds): string
{
    $seconds = max(0, $seconds);
    if ($seconds < 60) {
        return "$seconds seconds";
    }
    $h = intdiv($seconds, 3600);
    $m = intdiv($seconds % 3600, 60);
    return $h > 0 ? "{$h} h {$m} min" : "{$m} min";
}
