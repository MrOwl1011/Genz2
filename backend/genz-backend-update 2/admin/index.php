<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';
require_admin_login();

// Six separate indexed COUNTs, deliberately not one JOIN across accounts/
// profiles/favorites/history — a single JOIN to get all these numbers "in
// one query" would produce *wrong* numbers via row fan-out, not just be
// slower, since each table has a many-to-one relationship to the one above
// it.
$pdo = db();
$totalAccounts = (int) $pdo->query('SELECT COUNT(*) FROM accounts')->fetchColumn();
$activeAccounts = (int) $pdo->query("SELECT COUNT(*) FROM accounts WHERE status = 'active'")->fetchColumn();
$totalProfiles = (int) $pdo->query('SELECT COUNT(*) FROM profiles WHERE deleted_at IS NULL')->fetchColumn();
$totalFavorites = (int) $pdo->query('SELECT COUNT(*) FROM favorites')->fetchColumn();
$totalHistory = (int) $pdo->query('SELECT COUNT(*) FROM history')->fetchColumn();

// "Today" means GMT+3's midnight, not MySQL's CURDATE() (the DB server's
// own local date, which may not even be UTC) — last_seen_at is stored in
// UTC, so the boundary needs to be converted to UTC before comparing.
$todayStartGmt3 = new DateTime('today', new DateTimeZone('+03:00'));
$todayStartUtc = (clone $todayStartGmt3)->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s');
$onlineTodayStmt = $pdo->prepare('SELECT COUNT(DISTINCT account_id) FROM devices WHERE last_seen_at >= :today_start');
$onlineTodayStmt->execute(['today_start' => $todayStartUtc]);
$onlineToday = (int) $onlineTodayStmt->fetchColumn();

// device_count / latest_device_name: accounts no longer carry
// username/server_url (see account_label()'s doc comment), so the most
// recently-seen device's name is the practical way to tell accounts apart
// in this list now.
$recentAccounts = $pdo->query(
    "SELECT a.account_id, a.username, a.status, a.last_login_at,
            (SELECT COUNT(*) FROM devices d WHERE d.account_id = a.account_id) AS device_count,
            (SELECT d.device_name FROM devices d WHERE d.account_id = a.account_id
             ORDER BY d.last_seen_at DESC LIMIT 1) AS latest_device_name
     FROM accounts a ORDER BY a.last_login_at DESC LIMIT 8"
)->fetchAll();

$pageTitle = 'Dashboard';
$activeNav = 'dashboard';
require __DIR__ . '/includes/layout_start.php';
?>
<h1>Dashboard</h1>

<div class="stat-grid">
  <div class="stat-tile"><div class="label">Total Accounts</div><div class="value"><?= $totalAccounts ?></div></div>
  <div class="stat-tile"><div class="label">Active Accounts</div><div class="value"><?= $activeAccounts ?></div></div>
  <div class="stat-tile"><div class="label">Total Profiles</div><div class="value"><?= $totalProfiles ?></div></div>
  <div class="stat-tile"><div class="label">Total Favorites</div><div class="value"><?= $totalFavorites ?></div></div>
  <div class="stat-tile"><div class="label">History Records</div><div class="value"><?= $totalHistory ?></div></div>
  <div class="stat-tile"><div class="label">Online Today</div><div class="value"><?= $onlineToday ?></div></div>
</div>

<h2>Recently Active Accounts</h2>
<div class="card table-wrap">
  <table>
    <thead><tr><th>Account</th><th>Devices</th><th>Status</th><th>Last Login</th><th></th></tr></thead>
    <tbody>
      <?php if (empty($recentAccounts)): ?>
        <tr><td colspan="5" class="muted">No accounts yet.</td></tr>
      <?php endif; ?>
      <?php foreach ($recentAccounts as $a): ?>
        <tr>
          <td><?= html_escape(account_label($a['username'], $a['account_id'], $a['latest_device_name'])) ?></td>
          <td class="muted"><?= (int) $a['device_count'] ?></td>
          <td><span class="badge <?= $a['status'] === 'active' ? 'active' : 'suspended' ?>"><?= html_escape($a['status']) ?></span></td>
          <td class="muted"><?= html_escape(admin_display_time($a['last_login_at'])) ?></td>
          <td><a href="account_detail.php?id=<?= urlencode($a['account_id']) ?>">View →</a></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div>

<?php require __DIR__ . '/includes/layout_end.php'; ?>
