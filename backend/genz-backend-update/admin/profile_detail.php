<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';
require_admin_login();

$pdo = db();
$profileId = (string) ($_GET['id'] ?? '');
$flash = null;
$flashType = 'success';

if ($profileId === '') {
    header('Location: accounts.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_valid_csrf();
    $action = (string) ($_POST['action'] ?? '');

    if ($action === 'clear_history') {
        $pdo->prepare('DELETE FROM history WHERE profile_id = :pid')->execute(['pid' => $profileId]);
        // See the doc comment on this column in schema.sql — without this,
        // the app has no way to know its local cache should be wiped too,
        // and just keeps showing what it already had.
        $pdo->prepare('UPDATE profiles SET history_cleared_at = NOW() WHERE profile_id = :pid')->execute(['pid' => $profileId]);
        $flash = 'History cleared.';
    } elseif ($action === 'clear_favorites') {
        $pdo->prepare('DELETE FROM favorites WHERE profile_id = :pid')->execute(['pid' => $profileId]);
        $pdo->prepare('UPDATE profiles SET favorites_cleared_at = NOW() WHERE profile_id = :pid')->execute(['pid' => $profileId]);
        $flash = 'Favorites cleared.';
    } elseif ($action === 'remove_favorite') {
        $favId = (int) ($_POST['favorite_row_id'] ?? 0);
        $pdo->prepare('DELETE FROM favorites WHERE id = :id AND profile_id = :pid')->execute(['id' => $favId, 'pid' => $profileId]);
        $flash = 'Favorite removed.';
    } elseif ($action === 'remove_history') {
        $histId = (int) ($_POST['history_row_id'] ?? 0);
        $pdo->prepare('DELETE FROM history WHERE id = :id AND profile_id = :pid')->execute(['id' => $histId, 'pid' => $profileId]);
        $flash = 'History entry removed.';
    } elseif ($action === 'copy_profile') {
        $destAccountId = trim((string) ($_POST['dest_account_id'] ?? ''));
        $destCheck = $pdo->prepare('SELECT username FROM accounts WHERE account_id = :id');
        $destCheck->execute(['id' => $destAccountId]);
        $destUsername = $destCheck->fetchColumn();

        if ($destUsername === false) {
            $flash = 'Destination account not found.';
            $flashType = 'error';
        } else {
            $destCountStmt = $pdo->prepare('SELECT COUNT(*) FROM profiles WHERE account_id = :id AND deleted_at IS NULL');
            $destCountStmt->execute(['id' => $destAccountId]);
            if ((int) $destCountStmt->fetchColumn() >= MAX_PROFILES_PER_ACCOUNT) {
                $flash = "That account already has the maximum of " . MAX_PROFILES_PER_ACCOUNT . ' profiles.';
                $flashType = 'error';
            } else {
                // $profile (the full display row, including the account
                // JOIN) isn't loaded until after this POST handler runs —
                // fetch just what's needed for the copy directly here
                // rather than reordering the rest of the file around it.
                $sourceStmt = $pdo->prepare('SELECT name, avatar, is_kids FROM profiles WHERE profile_id = :pid');
                $sourceStmt->execute(['pid' => $profileId]);
                $source = $sourceStmt->fetch();

                $newProfileId = admin_generate_uuid_v4();
                $pdo->beginTransaction();
                try {
                    $pdo->prepare(
                        'INSERT INTO profiles (profile_id, account_id, name, avatar, is_kids, created_at, updated_at)
                         VALUES (:pid, :aid, :name, :avatar, :is_kids, NOW(), NOW())'
                    )->execute([
                        'pid' => $newProfileId,
                        'aid' => $destAccountId,
                        'name' => $source['name'],
                        'avatar' => $source['avatar'],
                        'is_kids' => $source['is_kids'],
                    ]);

                    // Favorites/history rows carry a per-profile unique key
                    // (profile_id, stream_id, stream_type) — copying via
                    // INSERT ... SELECT with the new profile_id substituted
                    // in keeps that constraint intact without a per-row loop.
                    $pdo->prepare(
                        'INSERT INTO favorites (profile_id, stream_id, stream_type, title, poster_url, raw_data, updated_at)
                         SELECT :new_pid, stream_id, stream_type, title, poster_url, raw_data, updated_at
                         FROM favorites WHERE profile_id = :old_pid'
                    )->execute(['new_pid' => $newProfileId, 'old_pid' => $profileId]);

                    $pdo->prepare(
                        'INSERT INTO history (profile_id, stream_id, stream_type, episode_id, series_id,
                                               title, poster_url, position_seconds, duration_seconds, raw_data, updated_at)
                         SELECT :new_pid, stream_id, stream_type, episode_id, series_id,
                                title, poster_url, position_seconds, duration_seconds, raw_data, updated_at
                         FROM history WHERE profile_id = :old_pid'
                    )->execute(['new_pid' => $newProfileId, 'old_pid' => $profileId]);

                    $pdo->commit();
                    $flash = 'Profile copied to ' . $destUsername . ' (favorites and history included).';
                } catch (Throwable $e) {
                    $pdo->rollBack();
                    $flash = 'Copy failed. Nothing was changed.';
                    $flashType = 'error';
                }
            }
        }
    }
}

function admin_generate_uuid_v4(): string
{
    $data = random_bytes(16);
    $data[6] = chr((ord($data[6]) & 0x0f) | 0x40);
    $data[8] = chr((ord($data[8]) & 0x3f) | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
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

// ─── Destination account search (for "Copy Profile To Another Account") ──────
$destQuery = trim((string) ($_GET['dest_q'] ?? ''));
$destResults = [];
if ($destQuery !== '') {
    $destSearchStmt = $pdo->prepare(
        "SELECT account_id, username, server_url FROM accounts
         WHERE (username LIKE :q1 OR account_id LIKE :q2) AND account_id != :self
         ORDER BY last_login_at DESC LIMIT 10"
    );
    $destSearchStmt->execute([
        'q1' => '%' . $destQuery . '%',
        'q2' => '%' . $destQuery . '%',
        'self' => $profile['account_id'],
    ]);
    $destResults = $destSearchStmt->fetchAll();
}

$pageTitle = $profile['name'];
$activeNav = 'accounts';
require __DIR__ . '/includes/layout_start.php';
?>
<p><a href="account_detail.php?id=<?= urlencode($profile['account_id']) ?>">← Back to <?= html_escape($profile['username']) ?></a></p>
<h1><?= html_escape($profile['name']) ?> <?php if ($profile['is_kids']): ?><span class="badge active">Kids</span><?php endif; ?></h1>

<?php if ($flash !== null): ?>
  <div class="flash <?= $flashType ?>"><?= html_escape($flash) ?></div>
<?php endif; ?>

<h2>Copy Profile To Another Account</h2>
<div class="card">
  <p class="muted" style="margin-top:0;">Creates a new profile under a different account with the same name, avatar, and a copy of this profile's favorites and history. Doesn't affect this profile.</p>
  <form method="GET" class="search-bar">
    <input type="hidden" name="id" value="<?= html_escape($profileId) ?>">
    <input type="search" name="dest_q" placeholder="Search destination by username or account ID…" value="<?= html_escape($destQuery) ?>">
    <button type="submit" class="btn primary">Search</button>
  </form>
  <?php if ($destQuery !== ''): ?>
    <div class="table-wrap" style="margin-top:14px;">
      <table>
        <thead><tr><th>Username</th><th>Server</th><th></th></tr></thead>
        <tbody>
          <?php if (empty($destResults)): ?>
            <tr><td colspan="3" class="muted">No matching accounts.</td></tr>
          <?php endif; ?>
          <?php foreach ($destResults as $d): ?>
            <tr>
              <td><?= html_escape($d['username']) ?></td>
              <td class="muted"><?= html_escape($d['server_url']) ?></td>
              <td>
                <form class="inline" method="POST" onsubmit="return confirm('Copy this profile (with its favorites and history) to <?= html_escape(addslashes($d['username'])) ?>?');">
                  <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
                  <input type="hidden" name="dest_account_id" value="<?= html_escape($d['account_id']) ?>">
                  <input type="hidden" name="action" value="copy_profile">
                  <button type="submit" class="btn small primary">Copy Here</button>
                </form>
              </td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
</div>

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
          <td class="muted"><?= html_escape(admin_display_time($f['updated_at'])) ?></td>
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
          <td class="muted"><?= html_escape(admin_display_time($h['updated_at'])) ?></td>
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
