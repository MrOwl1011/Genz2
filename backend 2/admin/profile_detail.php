<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';
require_admin_login();

$pdo = db();
$profileId = (string) ($_GET['id'] ?? '');
$flash = null;

if ($profileId === '') {
    header('Location: accounts.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_valid_csrf();
    $action = (string) ($_POST['action'] ?? '');

    if ($action === 'clear_history') {
        $pdo->prepare('DELETE FROM history WHERE profile_id = :pid')->execute(['pid' => $profileId]);
        $flash = 'History cleared.';
    } elseif ($action === 'clear_favorites') {
        $pdo->prepare('DELETE FROM favorites WHERE profile_id = :pid')->execute(['pid' => $profileId]);
        $flash = 'Favorites cleared.';
    } elseif ($action === 'remove_favorite') {
        $favId = (int) ($_POST['favorite_row_id'] ?? 0);
        $pdo->prepare('DELETE FROM favorites WHERE id = :id AND profile_id = :pid')->execute(['id' => $favId, 'pid' => $profileId]);
        $flash = 'Favorite removed.';
    } elseif ($action === 'remove_history') {
        $histId = (int) ($_POST['history_row_id'] ?? 0);
        $pdo->prepare('DELETE FROM history WHERE id = :id AND profile_id = :pid')->execute(['id' => $histId, 'pid' => $profileId]);
        $flash = 'History entry removed.';
    }
}

$profileStmt = $pdo->prepare(
    'SELECT p.*, a.username, a.account_id
     FROM profiles p JOIN accounts a ON a.account_id = p.account_id
     WHERE p.profile_id = :pid'
);
$profileStmt->execute(['pid' => $profileId]);
$profile = $profileStmt->fetch();

if ($profile === false) {
    $pageTitle = 'Profile Not Found';
    require __DIR__ . '/includes/layout_start.php';
    echo '<div class="card">Profile not found. <a href="accounts.php">Back to accounts</a></div>';
    require __DIR__ . '/includes/layout_end.php';
    exit;
}

$favoritesStmt = $pdo->prepare('SELECT id, stream_id, stream_type, title, updated_at FROM favorites WHERE profile_id = :pid ORDER BY updated_at DESC');
$favoritesStmt->execute(['pid' => $profileId]);
$favorites = $favoritesStmt->fetchAll();

$historyStmt = $pdo->prepare('SELECT id, stream_id, stream_type, title, position_seconds, duration_seconds, updated_at FROM history WHERE profile_id = :pid ORDER BY updated_at DESC LIMIT 100');
$historyStmt->execute(['pid' => $profileId]);
$history = $historyStmt->fetchAll();

$pageTitle = $profile['name'];
$activeNav = 'accounts';
require __DIR__ . '/includes/layout_start.php';
?>
<p><a href="account_detail.php?id=<?= urlencode($profile['account_id']) ?>">← Back to <?= html_escape($profile['username']) ?></a></p>
<h1><?= html_escape($profile['name']) ?> <?php if ($profile['is_kids']): ?><span class="badge active">Kids</span><?php endif; ?></h1>

<?php if ($flash !== null): ?>
  <div class="flash success"><?= html_escape($flash) ?></div>
<?php endif; ?>

<h2>Favorites (<?= count($favorites) ?>)</h2>
<div class="card table-wrap">
  <?php if (!empty($favorites)): ?>
    <form method="POST" onsubmit="return confirm('Clear ALL favorites for this profile?');" style="margin-bottom:14px;">
      <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
      <input type="hidden" name="action" value="clear_favorites">
      <button type="submit" class="btn small danger">Clear All Favorites</button>
    </form>
  <?php endif; ?>
  <table>
    <thead><tr><th>Title</th><th>Type</th><th>Updated</th><th></th></tr></thead>
    <tbody>
      <?php if (empty($favorites)): ?>
        <tr><td colspan="4" class="muted">No favorites.</td></tr>
      <?php endif; ?>
      <?php foreach ($favorites as $f): ?>
        <tr>
          <td><?= html_escape($f['title']) ?></td>
          <td class="muted"><?= html_escape($f['stream_type']) ?></td>
          <td class="muted"><?= html_escape($f['updated_at']) ?></td>
          <td>
            <form class="inline" method="POST">
              <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
              <input type="hidden" name="favorite_row_id" value="<?= (int) $f['id'] ?>">
              <input type="hidden" name="action" value="remove_favorite">
              <button type="submit" class="btn small">Remove</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div>

<h2>History (<?= count($history) ?>, showing most recent 100)</h2>
<div class="card table-wrap">
  <?php if (!empty($history)): ?>
    <form method="POST" onsubmit="return confirm('Clear ALL history for this profile?');" style="margin-bottom:14px;">
      <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
      <input type="hidden" name="action" value="clear_history">
      <button type="submit" class="btn small danger">Clear All History</button>
    </form>
  <?php endif; ?>
  <table>
    <thead><tr><th>Title</th><th>Type</th><th>Progress</th><th>Updated</th><th></th></tr></thead>
    <tbody>
      <?php if (empty($history)): ?>
        <tr><td colspan="5" class="muted">No history.</td></tr>
      <?php endif; ?>
      <?php foreach ($history as $h): ?>
        <?php $pct = $h['duration_seconds'] > 0 ? round(100 * $h['position_seconds'] / $h['duration_seconds']) : 0; ?>
        <tr>
          <td><?= html_escape($h['title']) ?></td>
          <td class="muted"><?= html_escape($h['stream_type']) ?></td>
          <td class="muted"><?= $pct ?>%</td>
          <td class="muted"><?= html_escape($h['updated_at']) ?></td>
          <td>
            <form class="inline" method="POST">
              <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
              <input type="hidden" name="history_row_id" value="<?= (int) $h['id'] ?>">
              <input type="hidden" name="action" value="remove_history">
              <button type="submit" class="btn small">Remove</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
    </tbody>
  </table>
</div>

<?php require __DIR__ . '/includes/layout_end.php'; ?>
