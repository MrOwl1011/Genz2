<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';
require_once __DIR__ . '/../lib/app_settings.php';
require_once __DIR__ . '/../lib/smtp_mailer.php';

/**
 * Profile notifications: pick profiles to watch, and get an email whenever one
 * of them starts watching something new.
 *
 * The email is sent by lib/profile_watch.php from api/history/save.php, at the
 * moment the app records a new history row — there is nothing polling, and
 * nothing to schedule. This page only chooses who is watched, holds the SMTP
 * settings, and shows what was sent.
 */
require_admin_login();

$requiredTables = [
    'profile_watches' => 'migration_005_profile_notifications.sql',
    'notification_log' => 'migration_005_profile_notifications.sql',
    'app_settings' => 'migration_005_profile_notifications.sql',
];
$present = db()->query(
    "SELECT TABLE_NAME FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME IN ('profile_watches', 'notification_log', 'app_settings')"
)->fetchAll(PDO::FETCH_COLUMN);
$missing = array_values(array_diff(array_keys($requiredTables), $present));
if ($missing !== []) {
    http_response_code(503);
    $pageTitle = 'Notifications';
    $activeNav = 'notifications';
    require __DIR__ . '/includes/layout_start.php';
    ?>
    <h1>Notifications</h1>
    <div class="card">
      <h2 style="margin-top:0;">Database update needed</h2>
      <p>In cPanel, open <strong>phpMyAdmin</strong>, select your database, and run
         <code>backend/sql/migration_005_profile_notifications.sql</code> from the SQL tab.
         It is safe to run more than once. Reload this page afterwards.</p>
    </div>
    <?php
    require __DIR__ . '/includes/layout_end.php';
    exit;
}

$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_valid_csrf();
    $action = (string) ($_POST['action'] ?? '');

    if ($action === 'watch') {
        // INSERT IGNORE rather than a check first: the primary key already
        // makes watching the same profile twice a no-op.
        db()->prepare('INSERT IGNORE INTO profile_watches (profile_id) VALUES (:id)')
            ->execute(['id' => (string) ($_POST['profile_id'] ?? '')]);
        header('Location: notifications.php?done=watch');
        exit;
    } elseif ($action === 'unwatch') {
        db()->prepare('DELETE FROM profile_watches WHERE profile_id = :id')
            ->execute(['id' => (string) ($_POST['profile_id'] ?? '')]);
        header('Location: notifications.php?done=unwatch');
        exit;
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
            $error = 'Enter at least one valid email address to send notifications to.';
        } else {
            $values = [
                'smtp_host' => $host, 'smtp_port' => (string) $port, 'smtp_secure' => $secure,
                'smtp_user' => $user, 'smtp_from' => $from,
                'alert_to' => implode(', ', smtp_parse_recipients($to)),
            ];
            // Blank means "keep what is saved". The stored password is never
            // printed back into the page, so blank is the normal case.
            if ($pass !== '') {
                $values['smtp_pass'] = $pass;
            }
            settings_set($values);
            header('Location: notifications.php?done=smtp');
            exit;
        }
    } elseif ($action === 'smtp_test') {
        try {
            smtp_send(
                smtp_load_config(),
                '[GENz+] Test email',
                "This is a test from the GENz+ admin panel.\n\n"
                . "If you are reading it, profile notifications will reach this address.\n"
            );
            header('Location: notifications.php?done=sent');
            exit;
        } catch (RuntimeException $e) {
            $error = 'Test email failed: ' . $e->getMessage();
        }
    }
}

// Keeps the log from growing without limit; this page is the only reader.
db()->exec('DELETE FROM notification_log WHERE created_at < NOW() - INTERVAL 30 DAY');

$watched = db()->query(
    'SELECT w.profile_id, p.name AS profile_name, p.account_id, a.username,
            (SELECT COUNT(*) FROM notification_log n WHERE n.profile_id = w.profile_id) AS sent_count
       FROM profile_watches w
       JOIN profiles p ON p.profile_id = w.profile_id
       LEFT JOIN accounts a ON a.account_id = p.account_id
      ORDER BY p.name'
)->fetchAll();

$query = trim((string) ($_GET['q'] ?? ''));
$results = [];
if ($query !== '') {
    // Search by profile name, account username or account id, matching how
    // the Copy Profiles page finds accounts.
    $stmt = db()->prepare(
        "SELECT p.profile_id, p.name AS profile_name, p.account_id, a.username
           FROM profiles p
           LEFT JOIN accounts a ON a.account_id = p.account_id
          WHERE p.deleted_at IS NULL
            AND (p.name LIKE :q1 OR a.username LIKE :q2 OR p.account_id LIKE :q3)
          ORDER BY p.name
          LIMIT 40"
    );
    $like = '%' . $query . '%';
    $stmt->execute(['q1' => $like, 'q2' => $like, 'q3' => $like]);
    $results = $stmt->fetchAll();
}

$log = db()->query(
    'SELECT profile_name, title, stream_type, sent, error, created_at
       FROM notification_log ORDER BY id DESC LIMIT 25'
)->fetchAll();

$smtp = settings_get(SMTP_SETTING_NAMES);

$notices = [
    'watch' => 'Profile added to the watch list.',
    'unwatch' => 'Profile removed from the watch list.',
    'smtp' => 'Email settings saved. Send a test email to confirm them.',
    'sent' => 'Test email sent. Check the inbox, and the spam folder too.',
];
$notice = $notices[(string) ($_GET['done'] ?? '')] ?? null;

$pageTitle = 'Notifications';
$activeNav = 'notifications';
require __DIR__ . '/includes/layout_start.php';
?>
<h1>Notifications</h1>

<?php if ($notice !== null): ?>
  <div class="flash success"><?= html_escape($notice) ?></div>
<?php endif; ?>
<?php if ($error !== null): ?>
  <div class="flash error"><?= html_escape($error) ?></div>
<?php endif; ?>
<?php if ($watched !== [] && $smtp['smtp_host'] === ''): ?>
  <div class="flash error">Profiles are being watched, but no email settings have been saved yet, so nothing can be sent.</div>
<?php endif; ?>

<div class="card">
  <h2 style="margin-top:0;">Watched profiles</h2>
  <p class="muted" style="margin-top:0;">
    You get an email the moment one of these profiles starts watching something new. Continuing
    something already in their history does not send anything.
  </p>
  <?php if ($watched === []): ?>
    <p class="muted" style="margin-bottom:0;">No profiles are being watched. Find one below.</p>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Profile</th><th>Account</th><th>Sent</th><th></th></tr></thead>
        <tbody>
        <?php foreach ($watched as $row): ?>
          <tr>
            <td><strong><?= html_escape($row['profile_name']) ?></strong></td>
            <td class="muted"><?= html_escape(account_label($row['username'], (string) $row['account_id'])) ?></td>
            <td class="muted"><?= (int) $row['sent_count'] ?></td>
            <td style="text-align:right;">
              <form method="POST" style="margin:0;">
                <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
                <input type="hidden" name="action" value="unwatch">
                <input type="hidden" name="profile_id" value="<?= html_escape($row['profile_id']) ?>">
                <button type="submit" class="btn small danger">Stop watching</button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>

<div class="card">
  <h2 style="margin-top:0;">Add a profile</h2>
  <form method="GET" style="display:flex;gap:10px;flex-wrap:wrap;margin-bottom:14px;">
    <input type="search" name="q" value="<?= html_escape($query) ?>" placeholder="Profile name, username or account id"
           style="flex:1;min-width:240px;padding:9px 12px;">
    <button type="submit" class="btn">Search</button>
  </form>
  <?php if ($query !== '' && $results === []): ?>
    <p class="muted" style="margin:0;">Nothing matched “<?= html_escape($query) ?>”.</p>
  <?php elseif ($results !== []): ?>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Profile</th><th>Account</th><th></th></tr></thead>
        <tbody>
        <?php foreach ($results as $row):
          $already = in_array($row['profile_id'], array_column($watched, 'profile_id'), true);
        ?>
          <tr>
            <td><strong><?= html_escape($row['profile_name']) ?></strong></td>
            <td class="muted"><?= html_escape(account_label($row['username'], (string) $row['account_id'])) ?></td>
            <td style="text-align:right;">
              <?php if ($already): ?>
                <span class="muted">Watching</span>
              <?php else: ?>
                <form method="POST" style="margin:0;">
                  <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
                  <input type="hidden" name="action" value="watch">
                  <input type="hidden" name="profile_id" value="<?= html_escape($row['profile_id']) ?>">
                  <button type="submit" class="btn small primary">Watch</button>
                </form>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>

<div class="card">
  <h2 style="margin-top:0;">Email settings</h2>
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
        <input type="text" id="smtp_user" name="smtp_user" autocomplete="off" value="<?= html_escape($smtp['smtp_user']) ?>">
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
      <label for="alert_to">Send notifications to <span class="muted">(separate several addresses with commas)</span></label>
      <input type="text" id="alert_to" name="alert_to" required value="<?= html_escape($smtp['alert_to']) ?>" placeholder="you@example.com">
    </div>
    <button type="submit" class="btn primary">Save email settings</button>
  </form>
  <form method="POST" style="margin-top:10px;">
    <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
    <input type="hidden" name="action" value="smtp_test">
    <button type="submit" class="btn" <?= $smtp['smtp_host'] === '' ? 'disabled' : '' ?>>Send test email</button>
  </form>
</div>

<div class="card">
  <h2 style="margin-top:0;">Recent notifications</h2>
  <?php if ($log === []): ?>
    <p class="muted" style="margin-bottom:0;">Nothing yet. Entries appear here as watched profiles start new things.</p>
  <?php else: ?>
    <div class="table-wrap">
      <table>
        <thead><tr><th>When</th><th>Profile</th><th>Title</th><th>Email</th></tr></thead>
        <tbody>
        <?php foreach ($log as $row): ?>
          <tr>
            <td class="muted"><?= html_escape(admin_display_time($row['created_at'])) ?></td>
            <td><?= html_escape($row['profile_name']) ?></td>
            <td class="muted"><?= html_escape($row['title']) ?></td>
            <td>
              <?php if ((int) $row['sent'] === 1): ?>
                <span class="badge active">Sent</span>
              <?php else: ?>
                <span class="muted" style="color:#f19093;"><?= html_escape($row['error'] ?? 'Failed') ?></span>
              <?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>

<style>
  .grid2 { display:grid; grid-template-columns:repeat(auto-fit, minmax(240px, 1fr)); gap:0 16px; }
</style>
<?php require __DIR__ . '/includes/layout_end.php'; ?>
