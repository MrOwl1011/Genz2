<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/app_settings.php';
require_once __DIR__ . '/server_probe.php';
require_once __DIR__ . '/smtp_mailer.php';

/**
 * The server watcher's core, shared by the two ways it can be started:
 *
 *  - cron/monitor_servers.php, a cPanel cron command, which stays alive for
 *    about 50 seconds and sweeps every 5;
 *  - monitor/run.php, a URL an external cron site calls, which must finish
 *    well inside the ~30 seconds such sites wait.
 *
 * Both do the same check, record and alert steps. They differ only in how
 * long they may keep starting new probes, which is why that is a parameter.
 *
 * Emails go out only when a server's state changes: one when it goes down,
 * one when it comes back. A failed check is repeated once after a short pause
 * before it counts, so a single dropped connection does not send an alert.
 */

const WATCH_RETRY_DELAY_SECONDS = 3;

/**
 * Takes the single-runner lock, or returns null if another run holds it.
 * Both entry points share one lock, so a cPanel cron run and a URL call can
 * never check the same server at the same time.
 *
 * @return resource|null
 */
function watch_acquire_lock()
{
    $lock = fopen(sys_get_temp_dir() . '/genz_monitor_' . md5(__DIR__) . '.lock', 'c');
    if ($lock === false || !flock($lock, LOCK_EX | LOCK_NB)) {
        return null;
    }
    return $lock;
}

/**
 * Records that the checker ran. Written through NOW() rather than from PHP,
 * so the admin page can compare it with NOW() and the database's own timezone
 * cancels out.
 */
function watch_heartbeat(PDO $pdo): void
{
    $pdo->exec(
        "INSERT INTO app_settings (name, value) VALUES ('monitor_last_run', NOW())
         ON DUPLICATE KEY UPDATE value = NOW()"
    );
}

/**
 * One sweep over the servers that are due.
 *
 * Stops starting new probes once $stopStartingAt (a microtime) has passed.
 * A server is claimed only as it is probed, so any not reached stay due and
 * are picked up by the next run, rather than being skipped for a whole
 * interval.
 *
 * @return array{checked: int, deferred: int, alerts: int}
 */
function watch_pass(PDO $pdo, float $stopStartingAt): array
{
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

    $tally = ['checked' => 0, 'deferred' => 0, 'alerts' => 0];

    foreach ($due as $row) {
        if (microtime(true) >= $stopStartingAt) {
            $tally['deferred']++;
            continue;
        }

        // Claim before probing: a slow probe must not leave the server looking
        // due to a concurrent or following sweep and get checked twice.
        $claim->execute(['seconds' => (int) $row['interval_seconds'], 'id' => $row['server_id']]);

        $result = probe_server((string) $row['url']);
        if (!$result['up']) {
            sleep(WATCH_RETRY_DELAY_SECONDS);
            $result = probe_server((string) $row['url']);
        }
        $tally['checked']++;

        $wasUp = $row['last_up'] === null ? null : ((int) $row['last_up'] === 1);
        // The first observation of a server counts as a change: it starts the
        // "since" clock, and a server already down when watching begins is
        // worth an email.
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
            $tally['alerts']++;
        }
    }

    return $tally;
}

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
    $body .= "\nGENz+ server monitor. You get one email when a server goes down and\n"
        . "one when it comes back.\n";

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
