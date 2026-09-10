<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

/**
 * Server status board: a list of IPTV server URLs, each probed live when the
 * page opens.
 *
 * Admin-only, and entirely outside the app — nothing the app calls reads
 * monitored_servers. The page renders immediately and the statuses fill in
 * afterwards (see the script below), so one slow or dead server never holds
 * up the rest of the list.
 */
require_admin_login();

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
            $insert = db()->prepare('INSERT INTO monitored_servers (label, url) VALUES (:label, :url)');
            $insert->execute(['label' => $label, 'url' => $url]);
            header('Location: servers.php?added=1');
            exit;
        }
    } elseif ($action === 'delete') {
        $delete = db()->prepare('DELETE FROM monitored_servers WHERE id = :id');
        $delete->execute(['id' => (int) ($_POST['id'] ?? 0)]);
        header('Location: servers.php?removed=1');
        exit;
    }
}

$servers = db()->query('SELECT id, label, url FROM monitored_servers ORDER BY label, id')->fetchAll();

$pageTitle = 'Servers';
$activeNav = 'servers';
require __DIR__ . '/includes/layout_start.php';
?>
<h1>Servers</h1>

<?php if (isset($_GET['added'])): ?>
  <div class="flash success">Server added.</div>
<?php elseif (isset($_GET['removed'])): ?>
  <div class="flash success">Server removed.</div>
<?php endif; ?>
<?php if ($error !== null): ?>
  <div class="flash error"><?= html_escape($error) ?></div>
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
          <tr><th>Status</th><th>Name</th><th>URL</th><th>Response</th><th></th></tr>
        </thead>
        <tbody>
        <?php foreach ($servers as $row): ?>
          <tr data-id="<?= (int) $row['id'] ?>">
            <td><span class="status pending">Checking</span></td>
            <td><strong><?= html_escape($row['label'] !== '' ? $row['label'] : '—') ?></strong></td>
            <td class="muted" style="word-break:break-all;"><?= html_escape($row['url']) ?></td>
            <td class="muted detail">—</td>
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

<style>
  .status { display:inline-flex; align-items:center; gap:7px; padding:4px 10px; border-radius:999px; font-size:12px; font-weight:700; }
  .status::before { content:''; width:7px; height:7px; border-radius:50%; background:currentColor; }
  .status.pending { color:var(--ink-muted); background:rgba(255,255,255,0.06); }
  .status.up { color:#6bd99a; background:rgba(42,166,92,0.14); }
  .status.down { color:#f19093; background:rgba(229,72,77,0.14); }
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
