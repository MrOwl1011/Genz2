<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';
require_admin_login();

$pdo = db();
$flash = null;
$flashType = 'success';

// ─── Mutating actions (suspend / unsuspend / delete) ─────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_valid_csrf();

    $action = (string) ($_POST['action'] ?? '');
    $accountId = (string) ($_POST['account_id'] ?? '');

    if ($accountId === '') {
        $flash = 'Missing account.';
        $flashType = 'error';
    } elseif ($action === 'suspend') {
        $stmt = $pdo->prepare("UPDATE accounts SET status = 'suspended' WHERE account_id = :id");
        $stmt->execute(['id' => $accountId]);
        $flash = 'Account suspended.';
    } elseif ($action === 'unsuspend') {
        $stmt = $pdo->prepare("UPDATE accounts SET status = 'active' WHERE account_id = :id");
        $stmt->execute(['id' => $accountId]);
        $flash = 'Account reactivated.';
    } elseif ($action === 'delete') {
        // Cascades to profiles/favorites/history/devices/device_tokens via
        // the FK ON DELETE CASCADE constraints in schema.sql.
        $stmt = $pdo->prepare('DELETE FROM accounts WHERE account_id = :id');
        $stmt->execute(['id' => $accountId]);
        $flash = 'Account and all its data deleted.';
    } else {
        $flash = 'Unknown action.';
        $flashType = 'error';
    }
}

// ─── Search / filter / paginate ───────────────────────────────────────────────
$query = trim((string) ($_GET['q'] ?? ''));
$statusFilter = (string) ($_GET['status'] ?? '');
$page = max(1, (int) ($_GET['page'] ?? 1));
$perPage = 20;
$offset = ($page - 1) * $perPage;

$where = [];
$params = [];
if ($query !== '') {
    // Four distinct placeholder names bound to the same value — PDO with
    // native prepares (PDO::ATTR_EMULATE_PREPARES = false, see lib/db.php)
    // does not support the same named placeholder appearing more than once
    // in one query.
    //
    // username/server_url still match for the shrinking set of legacy
    // accounts that haven't gone through migrate_legacy.php yet (see
    // account_label()'s doc comment) — every new account has neither, so
    // device_name is the practical way to find one by search now.
    $where[] = '(username LIKE :q1 OR server_url LIKE :q2 OR account_id LIKE :q3
                 OR EXISTS (SELECT 1 FROM devices d WHERE d.account_id = accounts.account_id AND d.device_name LIKE :q4))';
    $params['q1'] = '%' . $query . '%';
    $params['q2'] = '%' . $query . '%';
    $params['q3'] = '%' . $query . '%';
    $params['q4'] = '%' . $query . '%';
}
if ($statusFilter === 'active' || $statusFilter === 'suspended') {
    $where[] = 'status = :status';
    $params['status'] = $statusFilter;
}
$whereSql = $where ? ('WHERE ' . implode(' AND ', $where)) : '';

$countStmt = $pdo->prepare("SELECT COUNT(*) FROM accounts $whereSql");
$countStmt->execute($params);
$totalCount = (int) $countStmt->fetchColumn();
$totalPages = max(1, (int) ceil($totalCount / $perPage));

$listStmt = $pdo->prepare(
    "SELECT accounts.account_id, accounts.username, accounts.status, accounts.created_at, accounts.last_login_at,
            (SELECT COUNT(*) FROM devices d WHERE d.account_id = accounts.account_id) AS device_count,
            (SELECT d.device_name FROM devices d WHERE d.account_id = accounts.account_id
             ORDER BY d.last_seen_at DESC LIMIT 1) AS latest_device_name
     FROM accounts $whereSql ORDER BY last_login_at DESC LIMIT :limit OFFSET :offset"
);
foreach ($params as $key => $value) {
    $listStmt->bindValue($key, $value);
}
$listStmt->bindValue('limit', $perPage, PDO::PARAM_INT);
$listStmt->bindValue('offset', $offset, PDO::PARAM_INT);
$listStmt->execute();
$accounts = $listStmt->fetchAll();

$pageTitle = 'Accounts';
$activeNav = 'accounts';
require __DIR__ . '/includes/layout_start.php';

function accounts_query_string(int $page, string $query, string $status): string
{
    return http_build_query(['q' => $query, 'status' => $status, 'page' => $page]);
}
?>
<h1>Accounts</h1>

<?php if ($flash !== null): ?>
  <div class="flash <?= $flashType ?>"><?= html_escape($flash) ?></div>
<?php endif; ?>

<form method="GET" class="search-bar">
  <input type="search" name="q" placeholder="Search device name or account ID…" value="<?= html_escape($query) ?>">
  <select name="status" style="background:var(--surface-elevated);border:1px solid var(--border);border-radius:10px;color:var(--ink);padding:10px 12px;">
    <option value="" <?= $statusFilter === '' ? 'selected' : '' ?>>All statuses</option>
    <option value="active" <?= $statusFilter === 'active' ? 'selected' : '' ?>>Active</option>
    <option value="suspended" <?= $statusFilter === 'suspended' ? 'selected' : '' ?>>Suspended</option>
  </select>
  <button type="submit" class="btn primary">Search</button>
</form>

<div class="card table-wrap">
  <table>
    <thead><tr><th>Account</th><th>Devices</th><th>Status</th><th>Last Login</th><th>Actions</th></tr></thead>
    <tbody>
      <?php if (empty($accounts)): ?>
        <tr><td colspan="5" class="muted">No accounts match.</td></tr>
      <?php endif; ?>
      <?php foreach ($accounts as $a): ?>
        <tr>
          <td><a href="account_detail.php?id=<?= urlencode($a['account_id']) ?>"><?= html_escape(account_label($a['username'], $a['account_id'], $a['latest_device_name'])) ?></a></td>
          <td class="muted"><?= (int) $a['device_count'] ?></td>
          <td><span class="badge <?= $a['status'] === 'active' ? 'active' : 'suspended' ?>"><?= html_escape($a['status']) ?></span></td>
          <td class="muted"><?= html_escape(admin_display_time($a['last_login_at'])) ?></td>
          <td>
            <?php if ($a['status'] === 'active'): ?>
              <form class="inline" method="POST" onsubmit="return confirm('Suspend this account?');">
                <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
                <input type="hidden" name="account_id" value="<?= html_escape($a['account_id']) ?>">
                <input type="hidden" name="action" value="suspend">
                <button type="submit" class="btn small">Suspend</button>
              </form>
            <?php else: ?>
              <form class="inline" method="POST">
                <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
                <input type="hidden" name="account_id" value="<?= html_escape($a['account_id']) ?>">
                <input type="hidden" name="action" value="unsuspend">
                <button type="submit" class="btn small">Unsuspend</button>
              </form>
            <?php endif; ?>
            <form class="inline" method="POST" onsubmit="return confirm('Permanently delete this account and ALL its data (profiles, favorites, history, devices)? This cannot be undone.');">
              <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
              <input type="hidden" name="account_id" value="<?= html_escape($a['account_id']) ?>">
              <input type="hidden" name="action" value="delete">
              <button type="submit" class="btn small danger">Delete</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div>

<?php if ($totalPages > 1): ?>
<div class="pagination">
  <?php for ($p = 1; $p <= $totalPages; $p++): ?>
    <a class="btn small <?= $p === $page ? 'primary' : '' ?>" href="?<?= accounts_query_string($p, $query, $statusFilter) ?>"><?= $p ?></a>
  <?php endfor; ?>
</div>
<?php endif; ?>

<?php require __DIR__ . '/includes/layout_end.php'; ?>
