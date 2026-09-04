<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';
require_admin_login();

$pdo = db();
$accountId = (string) ($_GET['id'] ?? '');
$flash = null;
$flashType = 'success';

if ($accountId === '') {
    header('Location: accounts.php');
    exit;
}

// ─── Mutating actions ──────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_valid_csrf();
    $action = (string) ($_POST['action'] ?? '');

    if ($action === 'suspend') {
        $pdo->prepare("UPDATE accounts SET status = 'suspended' WHERE account_id = :id")->execute(['id' => $accountId]);
        $flash = 'Account suspended.';
    } elseif ($action === 'unsuspend') {
        $pdo->prepare("UPDATE accounts SET status = 'active' WHERE account_id = :id")->execute(['id' => $accountId]);
        $flash = 'Account reactivated.';
    } elseif ($action === 'delete_account') {
        $pdo->prepare('DELETE FROM accounts WHERE account_id = :id')->execute(['id' => $accountId]);
        header('Location: accounts.php?deleted=1');
        exit;
    } elseif ($action === 'delete_profile') {
        $profileId = (string) ($_POST['profile_id'] ?? '');
        $stmt = $pdo->prepare(
            'UPDATE profiles SET deleted_at = NOW(), updated_at = NOW()
             WHERE profile_id = :pid AND account_id = :aid AND deleted_at IS NULL'
        );
        $stmt->execute(['pid' => $profileId, 'aid' => $accountId]);
        $flash = $stmt->rowCount() > 0 ? 'Profile deleted.' : 'Profile not found.';
        $flashType = $stmt->rowCount() > 0 ? 'success' : 'error';
    } elseif ($action === 'clear_profile_history' || $action === 'clear_profile_favorites') {
        // Ownership check as its own query, then a plain single-parameter
        // DELETE — PDO with native prepares (PDO::ATTR_EMULATE_PREPARES =
        // false, see lib/db.php) does not support the same named
        // placeholder appearing twice in one query, so this can't be one
        // combined statement with both :pid and :aid guarding the DELETE
        // directly.
        $profileId = (string) ($_POST['profile_id'] ?? '');
        $ownedCheck = $pdo->prepare('SELECT 1 FROM profiles WHERE profile_id = :pid AND account_id = :aid');
        $ownedCheck->execute(['pid' => $profileId, 'aid' => $accountId]);

        if ($ownedCheck->fetchColumn() === false) {
            $flash = 'Profile not found for this account.';
            $flashType = 'error';
        } elseif ($action === 'clear_profile_history') {
            $pdo->prepare('DELETE FROM history WHERE profile_id = :pid')->execute(['pid' => $profileId]);
            // Tells the app to actually wipe its own local cache for this
            // profile too — see the doc comment on this column in schema.sql.
            // Without this, the device just silently keeps showing what it
            // already had cached; the server-side delete alone is invisible
            // to the user.
            $pdo->prepare('UPDATE profiles SET history_cleared_at = NOW() WHERE profile_id = :pid')->execute(['pid' => $profileId]);
            $flash = 'History cleared for this profile.';
        } else {
            $pdo->prepare('DELETE FROM favorites WHERE profile_id = :pid')->execute(['pid' => $profileId]);
            $pdo->prepare('UPDATE profiles SET favorites_cleared_at = NOW() WHERE profile_id = :pid')->execute(['pid' => $profileId]);
            $flash = 'Favorites cleared for this profile.';
        }
    }
}

// ─── Load account ───────────────────────────────────────────────────────────────
$accountStmt = $pdo->prepare('SELECT * FROM accounts WHERE account_id = :id');
$accountStmt->execute(['id' => $accountId]);
$account = $accountStmt->fetch();

if ($account === false) {
    $pageTitle = 'Account Not Found';
    require __DIR__ . '/includes/layout_start.php';
    echo '<div class="card">Account not found. <a href="accounts.php">Back to accounts</a></div>';
    require __DIR__ . '/includes/layout_end.php';
    exit;
}

// Profiles + per-profile favorite/history counts (small N — at most 5 active
// profiles per account — so N+1-ish per-profile count queries here are fine;
// not worth a more complex single query for a handful of rows).
$profilesStmt = $pdo->prepare(
    'SELECT profile_id, name, avatar, is_kids, created_at, updated_at
     FROM profiles WHERE account_id = :id AND deleted_at IS NULL ORDER BY created_at ASC'
);
$profilesStmt->execute(['id' => $accountId]);
$profiles = $profilesStmt->fetchAll();

$favCountStmt = $pdo->prepare('SELECT COUNT(*) FROM favorites WHERE profile_id = :pid');
$histCountStmt = $pdo->prepare('SELECT COUNT(*) FROM history WHERE profile_id = :pid');
foreach ($profiles as &$p) {
    $favCountStmt->execute(['pid' => $p['profile_id']]);
    $p['favorite_count'] = (int) $favCountStmt->fetchColumn();
    $histCountStmt->execute(['pid' => $p['profile_id']]);
    $p['history_count'] = (int) $histCountStmt->fetchColumn();
}
unset($p);

$devicesStmt = $pdo->prepare('SELECT device_id, device_name, platform, last_seen_at FROM devices WHERE account_id = :id ORDER BY last_seen_at DESC');
$devicesStmt->execute(['id' => $accountId]);
$devices = $devicesStmt->fetchAll();

$pageTitle = $account['username'];
$activeNav = 'accounts';
require __DIR__ . '/includes/layout_start.php';
?>
<p><a href="accounts.php">← Back to Accounts</a></p>
<h1><?= html_escape($account['username']) ?> <span class="badge <?= $account['status'] === 'active' ? 'active' : 'suspended' ?>"><?= html_escape($account['status']) ?></span></h1>

<?php if ($flash !== null): ?>
  <div class="flash <?= $flashType ?>"><?= html_escape($flash) ?></div>
<?php endif; ?>

<div class="card">
  <table>
    <tr><th style="width:160px;">Account ID</th><td><code><?= html_escape($account['account_id']) ?></code></td></tr>
    <tr><th>Server URL</th><td><?= html_escape($account['server_url']) ?></td></tr>
    <tr><th>Created</th><td class="muted"><?= html_escape(admin_display_time($account['created_at'])) ?></td></tr>
    <tr><th>Last Login</th><td class="muted"><?= html_escape(admin_display_time($account['last_login_at'])) ?></td></tr>
  </table>
  <div style="margin-top:16px;display:flex;gap:10px;">
    <?php if ($account['status'] === 'active'): ?>
      <form method="POST" onsubmit="return confirm('Suspend this account?');">
        <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
        <input type="hidden" name="action" value="suspend">
        <button type="submit" class="btn">Suspend Account</button>
      </form>
    <?php else: ?>
      <form method="POST">
        <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
        <input type="hidden" name="action" value="unsuspend">
        <button type="submit" class="btn">Unsuspend Account</button>
      </form>
    <?php endif; ?>
    <form method="POST" onsubmit="return confirm('Permanently delete this account and ALL its data? This cannot be undone.');">
      <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
      <input type="hidden" name="action" value="delete_account">
      <button type="submit" class="btn danger">Delete Account</button>
    </form>
  </div>
</div>

<h2>Profiles (<?= count($profiles) ?>)</h2>
<div class="card table-wrap">
  <table>
    <thead><tr><th>Name</th><th>Kids</th><th>Favorites</th><th>History</th><th>Created</th><th>Actions</th></tr></thead>
    <tbody>
      <?php if (empty($profiles)): ?>
        <tr><td colspan="6" class="muted">No profiles.</td></tr>
      <?php endif; ?>
      <?php foreach ($profiles as $p): ?>
        <tr>
          <td><a href="profile_detail.php?id=<?= urlencode($p['profile_id']) ?>"><?= html_escape($p['name']) ?></a></td>
          <td class="muted"><?= $p['is_kids'] ? 'Yes' : 'No' ?></td>
          <td><?= $p['favorite_count'] ?></td>
          <td><?= $p['history_count'] ?></td>
          <td class="muted"><?= html_escape(admin_display_time($p['created_at'])) ?></td>
          <td>
            <form class="inline" method="POST" onsubmit="return confirm('Clear all favorites for this profile?');">
              <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
              <input type="hidden" name="profile_id" value="<?= html_escape($p['profile_id']) ?>">
              <input type="hidden" name="action" value="clear_profile_favorites">
              <button type="submit" class="btn small">Clear Favorites</button>
            </form>
            <form class="inline" method="POST" onsubmit="return confirm('Clear all history for this profile?');">
              <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
              <input type="hidden" name="profile_id" value="<?= html_escape($p['profile_id']) ?>">
              <input type="hidden" name="action" value="clear_profile_history">
              <button type="submit" class="btn small">Clear History</button>
            </form>
            <form class="inline" method="POST" onsubmit="return confirm('Delete this profile?');">
              <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
              <input type="hidden" name="profile_id" value="<?= html_escape($p['profile_id']) ?>">
              <input type="hidden" name="action" value="delete_profile">
              <button type="submit" class="btn small danger">Delete</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div>

<h2>Devices (<?= count($devices) ?>)</h2>
<div class="card table-wrap">
  <table>
    <thead><tr><th>Device</th><th>Platform</th><th>Last Seen</th></tr></thead>
    <tbody>
      <?php if (empty($devices)): ?>
        <tr><td colspan="3" class="muted">No devices.</td></tr>
      <?php endif; ?>
      <?php foreach ($devices as $d): ?>
        <tr>
          <td><?= html_escape($d['device_name']) ?></td>
          <td class="muted"><?= html_escape($d['platform']) ?></td>
          <td class="muted"><?= html_escape(admin_display_time($d['last_seen_at'])) ?></td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div>

<?php require __DIR__ . '/includes/layout_end.php'; ?>
