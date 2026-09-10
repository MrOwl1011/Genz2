<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';
require_once __DIR__ . '/../lib/app_settings.php';
require_once __DIR__ . '/../lib/smtp_mailer.php';

/**
 * Server status board: a list of IPTV server URLs, probed live whenever the
 * page opens, with optional background watching and email alerts.
 *
 * Admin-only and entirely outside the app. Nothing the app calls reads
 * monitored_servers, server_monitors or app_settings. The live column fills
 * in after the page renders, so one slow server never holds up the list. The
 * background watching is done by cron/monitor_servers.php, not by this page.
 */
require_admin_login();

// The tables this page needs, and the migration that creates each. Checked up
// front so a database whose migrations have not been run gets a page naming
// the file to run, not a bare HTTP 500 from the first query that touches a
// missing table — which is how an un-run migration_004 first showed up.
$requiredTables = [
    'monitored_servers' => 'migration_003_monitored_servers.sql',
    'server_monitors' => 'migration_004_server_monitoring.sql',
    'app_settings' => 'migration_004_server_monitoring.sql',
];
$presentTables = db()->query(
    "SELECT TABLE_NAME FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME IN ('monitored_servers', 'server_monitors', 'app_settings')"
)->fetchAll(PDO::FETCH_COLUMN);
$missingMigrations = [];
foreach ($requiredTables as $table => $file) {
    if (!in_array($table, $presentTables, true) && !in_array($file, $missingMigrations, true)) {
        $missingMigrations[] = $file;
    }
}
if ($missingMigrations !== []) {
    http_response_code(503);
    $pageTitle = 'Servers';
    $activeNav = 'servers';
    require __DIR__ . '/includes/layout_start.php';
    ?>
    <h1>Servers</h1>
    <div class="card">
      <h2 style="margin-top:0;">Database update needed</h2>
      <p>This page needs <?= count($missingMigrations) === 1 ? 'a table that has' : 'tables that have' ?> not been created yet.
         In cPanel, open <strong>phpMyAdmin</strong>, select your database, and run
         <?= count($missingMigrations) === 1 ? 'this file' : 'these files, in this order' ?> from the SQL tab:</p>
      <ol>
        <?php foreach ($missingMigrations as $file): ?>
          <li><code>backend/sql/<?= html_escape($file) ?></code></li>
        <?php endforeach; ?>
      </ol>
      <p class="muted" style="margin-bottom:0;">Each is safe to run more than once. Reload this page afterwards.</p>
    </div>
    <?php
    require __DIR__ . '/includes/layout_end.php';
    exit;
}

const WATCH_MIN_SECONDS = 30;
const WATCH_MAX_SECONDS = 86400;

$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_valid_csrf();
    $action = (string) ($_POST['action'] ?? '');

    if ($action === 'add') {
        $label = trim((string) ($_POST['label'] ?? ''));
        $url = trim((string) ($_POST['url'] ?? ''));
        $parts = parse_url($url);

        if ($url === '' || mb_strlen($url) > 500) {
            $error = 'Enter a URL of 500 characters or fewer.';
        } elseif ($parts === false || !isset($parts['host'], $parts['scheme'])
            || !in_array(strtolower($parts['scheme']), ['http', 'https'], true)) {
            $error = 'The URL must start with http:// or https://, for example http://example.com:8080';
        } elseif (mb_strlen($label) > 80) {
            $error = 'Keep the name to 80 characters or fewer.';
        } else {
            db()->prepare('INSERT INTO monitored_servers (label, url) VALUES (:label, :url)')
                ->execute(['label' => $label, 'url' => $url]);
            header('Location: servers.php?done=added');
            exit;
        }
    } elseif ($action === 'delete') {
        // Its server_monitors row goes with it, by the foreign key.
        db()->prepare('DELETE FROM monitored_servers WHERE id = :id')
            ->execute(['id' => (int) ($_POST['id'] ?? 0)]);
        header('Location: servers.php?done=removed');
        exit;
    } elseif ($action === 'watch') {
        $id = (int) ($_POST['id'] ?? 0);
        $enabled = isset($_POST['enabled']) ? 1 : 0;
        $interval = (int) ($_POST['interval'] ?? 0);

        $exists = db()->prepare('SELECT 1 FROM monitored_servers WHERE id = :id');
        $exists->execute(['id' => $id]);

        if ($exists->fetchColumn() === false) {
            $error = 'That server is no longer listed.';
        } elseif ($interval < WATCH_MIN_SECONDS || $interval > WATCH_MAX_SECONDS) {
            $error = 'Check every ' . WATCH_MIN_SECONDS . ' to ' . WATCH_MAX_SECONDS . ' seconds.';
        } else {
            // Due immediately, so a change takes effect on the watcher's next
            // pass. Switching off forgets the last state: otherwise a server
            // that went down while unwatched would send a "back up" email the
            // moment it was watched again.
            db()->prepare(
                'INSERT INTO server_monitors (server_id, enabled, interval_seconds, next_check_at)
                 VALUES (:id, :enabled, :interval, NOW())
                 ON DUPLICATE KEY UPDATE
                   enabled = :enabled_again,
                   interval_seconds = :interval_again,
                   next_check_at = NOW(),
                   last_up = IF(:enabled_third = 1, last_up, NULL),
                   status_since = IF(:enabled_fourth = 1, status_since, NULL)'
            )->execute([
                'id' => $id,
                'enabled' => $enabled, 'enabled_again' => $enabled,
                'enabled_third' => $enabled, 'enabled_fourth' => $enabled,
                'interval' => $interval, 'interval_again' => $interval,
            ]);
            header('Location: servers.php?done=watch');
            exit;
        }
    } elseif ($action === 'smtp_save') {
        $host = trim((string) ($_POST['smtp_host'] ?? ''));
        $port = (int) ($_POST['smtp_port'] ?? 0);
        $secure = (string) ($_POST['smtp_secure'] ?? 'tls');
        $user = trim((string) ($_POST['smtp_user'] ?? ''));
        $pass = (string) ($_POST['smtp_pass'] ?? '');
        $from = trim((string) ($_POST['smtp_from'] ?? ''));
        $to = trim((string) ($_POST['alert_to'] ?? ''));

        if ($host === '' || $port < 1 || $port > 65535) {
            $error = 'Enter the SMTP host and a port between 1 and 65535.';
        } elseif (!in_array($secure, ['ssl', 'tls', 'none'], true)) {
            $error = 'Pick SSL, TLS or None for security.';
        } elseif ($from !== '' && filter_var($from, FILTER_VALIDATE_EMAIL) === false) {
            $error = 'The From address is not a valid email address.';
        } elseif (smtp_parse_recipients($to) === []) {
            $error = 'Enter at least one valid email address to send alerts to.';
        } else {
            $values = [
                'smtp_host' => $host, 'smtp_port' => (string) $port, 'smtp_secure' => $secure,
                'smtp_user' => $user, 'smtp_from' => $from,
                'alert_to' => implode(', ', smtp_parse_recipients($to)),
            ];
            // Blank means "keep what is saved". The stored password is never
            // printed back into the page, so an empty field is the normal case.
            if ($pass !== '') {
                $values['smtp_pass'] = $pass;
            }
            settings_set($values);
            header('Location: servers.php?done=smtp');
            exit;
        }
    } elseif ($action === 'token_new') {
        // Replacing the key is also how a leaked link is revoked: the old one
        // stops working the moment this saves.
        settings_set(['monitor_token' => bin2hex(random_bytes(24))]);
        header('Location: servers.php?done=token#checker');
        exit;
    } elseif ($action === 'smtp_test') {
        try {
            smtp_send(
                smtp_load_config(),
                '[GENz+] Test email',
                "This is a test from the GENz+ admin panel.\n\n"
                . "If you are reading it, server alerts will reach this address.\n"
            );
            header('Location: servers.php?done=sent');
            exit;
        } catch (RuntimeException $e) {
            $error = 'Test email failed: ' . $e->getMessage();
        }
    }
}

$servers = db()->query(
    'SELECT s.id, s.label, s.url,
            COALESCE(m.enabled, 0) AS enabled,
            COALESCE(m.interval_seconds, 300) AS interval_seconds,
            m.last_up, m.last_checked_at, m.status_since
       FROM monitored_servers s
       LEFT JOIN server_monitors m ON m.server_id = s.id
      ORDER BY s.label, s.id'
)->fetchAll();

$smtp = settings_get(array_merge(SMTP_SETTING_NAMES, ['monitor_mail_error', 'monitor_token']));
$watchedCount = count(array_filter($servers, static fn(array $r): bool => (int) $r['enabled'] === 1));

// How long ago the watcher last ran. NULL means it never has.
$sinceRun = db()->query(
    "SELECT TIMESTAMPDIFF(SECOND, value, NOW()) FROM app_settings WHERE name = 'monitor_last_run'"
)->fetchColumn();
// Eleven minutes: generous enough for a 5-minute external cron that misses a
// beat, so the warning means the checker has genuinely stopped rather than
// that it runs less often than every minute.
$watcherStale = $watchedCount > 0 && ($sinceRun === false || $sinceRun === null || (int) $sinceRun > 660);
$cronPath = realpath(__DIR__ . '/../cron/monitor_servers.php') ?: (dirname(__DIR__) . '/cron/monitor_servers.php');

// Built from this request so it is right wherever the panel is hosted.
// X-Forwarded-Proto covers HTTPS terminated in front of PHP, as Cloudflare does.
$https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || strtolower((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
$basePath = rtrim(str_replace('\\', '/', dirname(dirname((string) $_SERVER['SCRIPT_NAME']))), '/');
$triggerUrl = ($https ? 'https' : 'http') . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost')
    . $basePath . '/monitor/run.php?key=' . rawurlencode($smtp['monitor_token']);

$notices = [
    'added' => 'Server added.',
    'removed' => 'Server removed.',
    'watch' => 'Watching settings saved.',
    'smtp' => 'Email settings saved. Send a test email to confirm them.',
    'sent' => 'Test email sent. Check the inbox, and the spam folder too.',
    'token' => 'Checker link created. Any older link has stopped working.',
];
$notice = $notices[(string) ($_GET['done'] ?? '')] ?? null;

$pageTitle = 'Servers';
$activeNav = 'servers';
require __DIR__ . '/includes/layout_start.php';
?>
<h1>Servers</h1>

<?php if ($notice !== null): ?>
  <div class="flash success"><?= html_escape($notice) ?></div>
<?php endif; ?>
<?php if ($error !== null): ?>
  <div class="flash error"><?= html_escape($error) ?></div>
<?php endif; ?>
<?php if ($watcherStale): ?>
  <div class="flash error">
    <?= $watchedCount ?> server<?= $watchedCount === 1 ? ' is' : 's are' ?> set to be watched, but the background
    checker has not run<?= $sinceRun === false || $sinceRun === null ? ' yet' : ' for ' . (int) round((int) $sinceRun / 60) . ' minutes' ?>.
    Set up the background checker at the bottom of this page.
  </div>
<?php endif; ?>
<?php if ($smtp['monitor_mail_error'] !== ''): ?>
  <div class="flash error">The last alert email could not be sent: <?= html_escape($smtp['monitor_mail_error']) ?></div>
<?php endif; ?>

<div class="card">
  <div style="display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:14px;">
    <strong id="summary" class="muted"><?= count($servers) === 0 ? 'No servers yet' : 'Checking…' ?></strong>
    <?php if (count($servers) > 0): ?>
      <button type="button" class="btn small" id="recheck">Check again</button>
    <?php endif; ?>
  </div>

  <?php if (count($servers) === 0): ?>
    <p class="muted" style="margin:0;">Add a server below and its status will show here every time you open this page.</p>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Now</th><th>Name</th><th>URL</th><th>Response</th><th>Watch &amp; email</th><th></th></tr>
        </thead>
        <tbody>
        <?php foreach ($servers as $row):
          $watching = (int) $row['enabled'] === 1;
        ?>
          <tr data-id="<?= (int) $row['id'] ?>">
            <td><span class="status pending">Checking</span></td>
            <td><strong><?= html_escape($row['label'] !== '' ? $row['label'] : '—') ?></strong></td>
            <td class="muted" style="word-break:break-all;"><?= html_escape($row['url']) ?></td>
            <td class="muted detail">—</td>
            <td>
              <form method="POST" class="watch">
                <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
                <input type="hidden" name="action" value="watch">
                <input type="hidden" name="id" value="<?= (int) $row['id'] ?>">
                <label><input type="checkbox" name="enabled" value="1" <?= $watching ? 'checked' : '' ?>> Watch</label>
                <span class="muted">every</span>
                <input type="number" name="interval" min="<?= WATCH_MIN_SECONDS ?>" max="<?= WATCH_MAX_SECONDS ?>"
                       value="<?= (int) $row['interval_seconds'] ?>" required>
                <span class="muted">sec</span>
                <button type="submit" class="btn small">Save</button>
              </form>
              <?php if ($watching): ?>
                <div class="watch-state muted">
                  <?php if ($row['last_up'] === null): ?>
                    Waiting for the first check
                  <?php else: ?>
                    <?= (int) $row['last_up'] === 1 ? 'Up' : '<span style="color:#f19093">Down</span>' ?>
                    since <?= html_escape(admin_display_time($row['status_since'])) ?>
                  <?php endif; ?>
                </div>
              <?php endif; ?>
            </td>
            <td style="text-align:right;">
              <form method="POST" onsubmit="return confirm('Remove this server?');" style="margin:0;">
                <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
                <input type="hidden" name="action" value="delete">
                <input type="hidden" name="id" value="<?= (int) $row['id'] ?>">
                <button type="submit" class="btn small danger">Remove</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
    <p class="muted" style="margin:12px 0 0;font-size:12.5px;">
      A watched server is checked when the background checker runs. If it runs every 5 minutes,
      use 300 seconds or more: a shorter interval cannot be honoured and behaves as 300.
    </p>
  <?php endif; ?>
</div>

<div class="card">
  <h2 style="margin-top:0;">Add a server</h2>
  <form method="POST">
    <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
    <input type="hidden" name="action" value="add">
    <div class="field">
      <label for="label">Name <span class="muted">(optional)</span></label>
      <input type="text" id="label" name="label" maxlength="80" placeholder="Main panel">
    </div>
    <div class="field">
      <label for="url">URL</label>
      <input type="url" id="url" name="url" required maxlength="500" placeholder="http://example.com:8080">
    </div>
    <button type="submit" class="btn primary">Add server</button>
  </form>
</div>

<div class="card">
  <h2 style="margin-top:0;">Email alerts</h2>
  <p class="muted" style="margin-top:0;">
    Watched servers send one email when they go down and one when they come back. A failed check is
    repeated once before it counts, so a single dropped connection does not send an alert.
  </p>
  <form method="POST">
    <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
    <input type="hidden" name="action" value="smtp_save">
    <div class="grid2">
      <div class="field">
        <label for="smtp_host">SMTP host</label>
        <input type="text" id="smtp_host" name="smtp_host" required value="<?= html_escape($smtp['smtp_host']) ?>" placeholder="mail.example.com">
      </div>
      <div class="field">
        <label for="smtp_port">Port</label>
        <input type="number" id="smtp_port" name="smtp_port" required min="1" max="65535"
               value="<?= html_escape($smtp['smtp_port'] !== '' ? $smtp['smtp_port'] : '587') ?>">
      </div>
      <div class="field">
        <label for="smtp_secure">Security</label>
        <select id="smtp_secure" name="smtp_secure">
          <?php foreach (['tls' => 'TLS / STARTTLS (usually 587)', 'ssl' => 'SSL (usually 465)', 'none' => 'None (usually 25)'] as $value => $text): ?>
            <option value="<?= $value ?>" <?= ($smtp['smtp_secure'] !== '' ? $smtp['smtp_secure'] : 'tls') === $value ? 'selected' : '' ?>><?= $text ?></option>
          <?php endforeach; ?>
        </select>
      </div>
      <div class="field">
        <label for="smtp_user">Username</label>
        <input type="text" id="smtp_user" name="smtp_user" autocomplete="off" value="<?= html_escape($smtp['smtp_user']) ?>" placeholder="alerts@example.com">
      </div>
      <div class="field">
        <label for="smtp_pass">Password</label>
        <input type="password" id="smtp_pass" name="smtp_pass" autocomplete="new-password"
               placeholder="<?= $smtp['smtp_pass'] !== '' ? 'Saved. Leave blank to keep it.' : '' ?>">
      </div>
      <div class="field">
        <label for="smtp_from">From address <span class="muted">(optional, defaults to the username)</span></label>
        <input type="email" id="smtp_from" name="smtp_from" value="<?= html_escape($smtp['smtp_from']) ?>">
      </div>
    </div>
    <div class="field">
      <label for="alert_to">Send alerts to <span class="muted">(separate several addresses with commas)</span></label>
      <input type="text" id="alert_to" name="alert_to" required value="<?= html_escape($smtp['alert_to']) ?>" placeholder="you@example.com">
    </div>
    <div style="display:flex;gap:10px;flex-wrap:wrap;">
      <button type="submit" class="btn primary">Save email settings</button>
    </div>
  </form>
  <form method="POST" style="margin-top:10px;">
    <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
    <input type="hidden" name="action" value="smtp_test">
    <button type="submit" class="btn" <?= $smtp['smtp_host'] === '' ? 'disabled' : '' ?>>Send test email</button>
  </form>
</div>

<div class="card" id="checker">
  <h2 style="margin-top:0;">Background checker</h2>
  <p class="muted" style="margin-top:0;">
    Watching needs something to start the checker on a schedule. Set up <strong>one</strong> of these.
    <?php if ($sinceRun !== false && $sinceRun !== null): ?>
      Last run: <strong><?= (int) $sinceRun < 90 ? 'just now' : html_escape((string) round((int) $sinceRun / 60)) . ' min ago' ?></strong>.
    <?php else: ?>
      It has not run yet.
    <?php endif; ?>
  </p>

  <h3 class="sub">External cron site, every 5 minutes</h3>
  <p class="muted">
    For hosting plans that cannot run cron every minute. On a site such as cron-job.org, create a job
    that opens this link every 5 minutes:
  </p>
  <?php if ($smtp['monitor_token'] === ''): ?>
    <form method="POST">
      <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
      <input type="hidden" name="action" value="token_new">
      <button type="submit" class="btn primary">Create checker link</button>
    </form>
  <?php else: ?>
    <pre class="cmd"><?= html_escape($triggerUrl) ?></pre>
    <p class="muted">
      Keep it private. Anyone with it can make the checker run early, though it shows them nothing about
      your servers. If it leaks, replace it.
    </p>
    <form method="POST" onsubmit="return confirm('The current link will stop working immediately. Replace it?');">
      <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
      <input type="hidden" name="action" value="token_new">
      <button type="submit" class="btn small">Replace link</button>
    </form>
  <?php endif; ?>

  <h3 class="sub">cPanel cron, every minute</h3>
  <p class="muted">If your plan allows it, choose <strong>Once Per Minute</strong> in cPanel's Cron Jobs and paste:</p>
  <pre class="cmd" style="margin-bottom:0;">/usr/local/bin/php <?= html_escape($cronPath) ?></pre>
</div>

<style>
  .status { display:inline-flex; align-items:center; gap:7px; padding:4px 10px; border-radius:999px; font-size:12px; font-weight:700; white-space:nowrap; }
  .status::before { content:''; width:7px; height:7px; border-radius:50%; background:currentColor; }
  .status.pending { color:var(--ink-muted); background:rgba(255,255,255,0.06); }
  .status.up { color:#6bd99a; background:rgba(42,166,92,0.14); }
  .status.down { color:#f19093; background:rgba(229,72,77,0.14); }
  form.watch { display:flex; align-items:center; gap:6px; flex-wrap:nowrap; margin:0; white-space:nowrap; }
  form.watch input[type=number] { width:84px; padding:6px 8px; }
  form.watch label { display:inline-flex; align-items:center; gap:5px; margin:0; font-weight:600; }
  .watch-state { font-size:12px; margin-top:5px; }
  .grid2 { display:grid; grid-template-columns:repeat(auto-fit, minmax(240px, 1fr)); gap:0 16px; }
  h3.sub { font-size:14px; margin:20px 0 6px; }
  pre.cmd { background:rgba(0,0,0,0.3); border:1px solid var(--border); border-radius:8px; padding:12px 14px; overflow-x:auto; font-size:13px; user-select:all; }
</style>

<script>
(() => {
  const csrf = <?= json_encode(csrf_token()) ?>;
  const rows = [...document.querySelectorAll('tr[data-id]')];
  const summary = document.getElementById('summary');
  const recheck = document.getElementById('recheck');
  if (!rows.length) return;

  function paint(row, state, text, detail) {
    const badge = row.querySelector('.status');
    badge.className = 'status ' + state;
    badge.textContent = text;
    row.querySelector('.detail').textContent = detail;
  }

  async function check(row) {
    paint(row, 'pending', 'Checking', '—');
    const body = new FormData();
    body.append('csrf_token', csrf);
    body.append('id', row.dataset.id);
    try {
      const res = await fetch('api/check_server.php', { method: 'POST', body, credentials: 'same-origin' });
      const data = await res.json();
      if (!data.success) { paint(row, 'down', 'Error', data.error || 'Check failed.'); return false; }
      const time = data.ms != null ? ` · ${data.ms} ms` : '';
      if (data.up) { paint(row, 'up', 'Up', `HTTP ${data.code}${time}`); return true; }
      paint(row, 'down', 'Down', (data.error || 'No response.') + time);
      return false;
    } catch (e) {
      // The panel itself did not answer — usually an expired admin session.
      paint(row, 'down', 'Error', 'Could not reach the admin panel. Reload the page.');
      return false;
    }
  }

  // Six at a time: fast, without every probe landing on shared hosting's
  // small PHP worker pool at once.
  async function run() {
    recheck.disabled = true;
    summary.textContent = 'Checking…';
    let up = 0, down = 0, next = 0;
    const worker = async () => {
      while (next < rows.length) {
        const ok = await check(rows[next++]);
        ok ? up++ : down++;
        summary.textContent = `${up} up · ${down} down`;
      }
    };
    await Promise.all(Array.from({ length: Math.min(6, rows.length) }, worker));
    recheck.disabled = false;
  }

  recheck.addEventListener('click', run);
  run();
})();
</script>
<?php require __DIR__ . '/includes/layout_end.php'; ?>
