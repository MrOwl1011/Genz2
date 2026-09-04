<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';
require_once __DIR__ . '/../lib/db.php';

/**
 * Two accounts side by side; drag a profile card from either side to the
 * other to copy it. Sits alongside the single-profile copy already in
 * account_detail.php rather than replacing it — that one is fine for a
 * quick one-off, this is for when you're actually working between two
 * accounts.
 *
 * Copies only, one profile at a time, and never modifies or removes
 * anything that already exists — see api/copy_profile.php's doc comment
 * for the full rules. The copy is a snapshot: the two profiles are
 * independent from the moment it lands and nothing syncs between them.
 *
 * Both panes are rendered server-side on load and refreshed via fetch()
 * afterwards. Deliberately no framework — the rest of this panel is plain
 * server-rendered PHP with no build step, and this doesn't justify
 * changing that.
 */
require_admin_login();

$pdo = db();

/** Accounts matching a search, with enough context to tell them apart. */
function search_accounts(PDO $pdo, string $query): array
{
    if ($query === '') return [];
    $like = '%' . $query . '%';
    $stmt = $pdo->prepare(
        "SELECT accounts.account_id, accounts.username, accounts.last_login_at,
                (SELECT COUNT(*) FROM profiles p
                  WHERE p.account_id = accounts.account_id AND p.deleted_at IS NULL) AS profile_count,
                (SELECT d.device_name FROM devices d
                  WHERE d.account_id = accounts.account_id
                  ORDER BY d.last_seen_at DESC LIMIT 1) AS latest_device_name
         FROM accounts
         WHERE accounts.username LIKE :q1
            OR accounts.account_id LIKE :q2
            OR EXISTS (SELECT 1 FROM devices d
                        WHERE d.account_id = accounts.account_id AND d.device_name LIKE :q3)
            OR EXISTS (SELECT 1 FROM profiles p
                        WHERE p.account_id = accounts.account_id
                          AND p.deleted_at IS NULL AND p.name LIKE :q4)
         ORDER BY accounts.last_login_at DESC
         LIMIT 12"
    );
    $stmt->execute(['q1' => $like, 'q2' => $like, 'q3' => $like, 'q4' => $like]);
    return $stmt->fetchAll();
}

/** One account's profiles, with the counts that make them distinguishable. */
function account_profiles(PDO $pdo, string $accountId): array
{
    $stmt = $pdo->prepare(
        'SELECT p.profile_id, p.name, p.avatar, p.is_kids,
                (SELECT COUNT(*) FROM favorites f WHERE f.profile_id = p.profile_id) AS favorites,
                (SELECT COUNT(*) FROM history h WHERE h.profile_id = p.profile_id) AS history
         FROM profiles p
         WHERE p.account_id = :account_id AND p.deleted_at IS NULL
         ORDER BY p.created_at ASC'
    );
    $stmt->execute(['account_id' => $accountId]);
    return $stmt->fetchAll();
}

// XHR: the panes re-render themselves through this after a copy or a search.
if (($_GET['fragment'] ?? '') !== '') {
    header('Content-Type: application/json; charset=utf-8');
    $fragment = (string) $_GET['fragment'];
    if ($fragment === 'search') {
        echo json_encode(['accounts' => search_accounts($pdo, trim((string) ($_GET['q'] ?? '')))]);
    } elseif ($fragment === 'profiles') {
        echo json_encode(['profiles' => account_profiles($pdo, trim((string) ($_GET['account_id'] ?? '')))]);
    } else {
        http_response_code(400);
        echo json_encode(['error' => 'unknown fragment']);
    }
    exit;
}

$pageTitle = 'Copy Profiles';
$activeNav = 'transfer';
require __DIR__ . '/includes/layout_start.php';
?>
<h1>Copy Profiles</h1>
<p class="muted" style="max-width:70ch">
  Search for an account on each side, then drag a profile from one to the
  other to copy it. The original is never changed, and nothing that already
  exists on the receiving account is touched — a copy only ever adds.
</p>

<div class="transfer" id="transfer">
  <?php foreach (['left', 'right'] as $side): ?>
    <section class="pane" data-side="<?= $side ?>">
      <div class="pane-search">
        <input type="search" class="acct-search" data-side="<?= $side ?>"
               placeholder="Search device, profile or account ID…" autocomplete="off">
        <div class="acct-results" data-side="<?= $side ?>" hidden></div>
      </div>
      <div class="pane-head" data-side="<?= $side ?>">
        <span class="muted">No account selected</span>
      </div>
      <div class="dropzone" data-side="<?= $side ?>">
        <p class="muted empty-hint">Pick an account to see its profiles.</p>
      </div>
    </section>
  <?php endforeach; ?>
</div>

<div class="toast" id="toast" hidden>
  <span id="toast-text"></span>
  <button type="button" id="toast-undo" class="btn small">Undo</button>
</div>

<style>
  .transfer { display:grid; grid-template-columns:1fr 1fr; gap:20px; margin-top:20px; }
  @media (max-width: 900px) { .transfer { grid-template-columns:1fr; } }
  .pane { background:var(--surface,#161b22); border:1px solid var(--border,#30363d);
          border-radius:12px; padding:14px; display:flex; flex-direction:column; gap:12px; min-height:340px; }
  .pane-search { position:relative; }
  .acct-search { width:100%; padding:9px 12px; border-radius:8px;
                 border:1px solid var(--border,#30363d); background:var(--bg,#0d1117);
                 color:inherit; font:inherit; }
  .acct-results { position:absolute; z-index:20; left:0; right:0; top:calc(100% + 4px);
                  background:var(--surface,#161b22); border:1px solid var(--border,#30363d);
                  border-radius:8px; max-height:260px; overflow:auto; }
  .acct-result { padding:9px 12px; cursor:pointer; border-bottom:1px solid var(--border,#30363d); }
  .acct-result:last-child { border-bottom:none; }
  .acct-result:hover, .acct-result:focus { background:rgba(127,127,127,.14); outline:none; }
  .acct-result .mono { font-family:ui-monospace,monospace; font-size:.78rem; opacity:.6; }
  .pane-head { font-weight:600; min-height:1.4em; }
  .dropzone { flex:1; border:2px dashed transparent; border-radius:10px; padding:6px;
              display:flex; flex-direction:column; gap:10px; transition:background .12s,border-color .12s; }
  .dropzone.over { border-color:#3fb950; background:rgba(63,185,80,.08); }
  .card { background:var(--bg,#0d1117); border:1px solid var(--border,#30363d);
          border-radius:10px; padding:11px 13px; cursor:grab;
          display:flex; align-items:center; gap:12px; }
  .card:active { cursor:grabbing; }
  .card.dragging { opacity:.45; }
  .card .grip { opacity:.4; font-size:1.1rem; line-height:1; }
  .card .meta { flex:1; min-width:0; }
  .card .nm { font-weight:600; }
  .card .sub { font-size:.78rem; opacity:.62; }
  .card .kid { font-size:.68rem; border:1px solid currentColor; border-radius:4px;
               padding:1px 5px; opacity:.75; }
  .card .send { font-size:.75rem; padding:5px 9px; white-space:nowrap; }
  .empty-hint { margin:auto; }
  .toast { position:fixed; left:50%; bottom:22px; transform:translateX(-50%);
           background:#1f6feb; color:#fff; padding:11px 16px; border-radius:9px;
           display:flex; align-items:center; gap:14px; z-index:80;
           box-shadow:0 8px 24px rgba(0,0,0,.35); }
  .toast .btn { background:rgba(255,255,255,.18); border:1px solid rgba(255,255,255,.35); color:#fff; }
</style>

<script>
(function () {
  var CSRF = <?= json_encode(csrf_token()) ?>;
  var selected = { left: null, right: null };
  var lastCopy = null;
  var toastTimer = null;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c];
    });
  }
  function other(side) { return side === 'left' ? 'right' : 'left'; }
  function pane(side, sel) { return document.querySelector('.pane[data-side="'+side+'"] '+sel); }

  function showToast(text, undoFn) {
    var t = document.getElementById('toast');
    document.getElementById('toast-text').textContent = text;
    var undo = document.getElementById('toast-undo');
    undo.hidden = !undoFn;
    undo.onclick = function () { if (undoFn) undoFn(); hideToast(); };
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, 9000);
  }
  function hideToast() { document.getElementById('toast').hidden = true; }

  // ---- account search ----
  document.querySelectorAll('.acct-search').forEach(function (input) {
    var side = input.dataset.side, timer = null;
    input.addEventListener('input', function () {
      clearTimeout(timer);
      var q = input.value.trim();
      var box = pane(side, '.acct-results');
      if (!q) { box.hidden = true; return; }
      timer = setTimeout(function () {
        fetch('profile_transfer.php?fragment=search&q=' + encodeURIComponent(q))
          .then(function (r) { return r.json(); })
          .then(function (d) {
            box.innerHTML = (d.accounts || []).map(function (a) {
              var label = a.username || a.latest_device_name || 'Account';
              return '<div class="acct-result" tabindex="0" data-id="' + esc(a.account_id) + '"' +
                     ' data-label="' + esc(label) + '">' +
                     '<div>' + esc(label) + ' · ' + a.profile_count + ' profile(s)</div>' +
                     '<div class="mono">' + esc(a.account_id.slice(0, 24)) + '…</div></div>';
            }).join('') || '<div class="acct-result">No matches</div>';
            box.hidden = false;
          });
      }, 220);
    });
    input.addEventListener('blur', function () {
      // Delay so a click on a result still registers before the box hides.
      setTimeout(function () { pane(side, '.acct-results').hidden = true; }, 180);
    });
  });

  document.addEventListener('click', function (e) {
    var res = e.target.closest('.acct-result');
    if (!res || !res.dataset.id) return;
    var side = res.closest('.pane').dataset.side;
    selectAccount(side, res.dataset.id, res.dataset.label);
  });

  function selectAccount(side, id, label) {
    selected[side] = id;
    pane(side, '.pane-head').innerHTML = esc(label) +
      ' <span class="mono muted">' + esc(id.slice(0, 12)) + '…</span>';
    pane(side, '.acct-results').hidden = true;
    loadProfiles(side);
  }

  function loadProfiles(side) {
    var id = selected[side];
    var zone = pane(side, '.dropzone');
    if (!id) { zone.innerHTML = '<p class="muted empty-hint">Pick an account to see its profiles.</p>'; return; }
    fetch('profile_transfer.php?fragment=profiles&account_id=' + encodeURIComponent(id))
      .then(function (r) { return r.json(); })
      .then(function (d) { renderProfiles(side, d.profiles || []); });
  }

  function renderProfiles(side, profiles) {
    var zone = pane(side, '.dropzone');
    if (!profiles.length) {
      zone.innerHTML = '<p class="muted empty-hint">No profiles on this account.</p>';
      return;
    }
    zone.innerHTML = profiles.map(function (p) {
      return '<div class="card" draggable="true" data-profile="' + esc(p.profile_id) + '">' +
        '<span class="grip">⠿</span>' +
        '<span class="meta"><span class="nm">' + esc(p.name) + '</span>' +
        (p.is_kids ? ' <span class="kid">KIDS</span>' : '') +
        '<div class="sub">' + p.favorites + ' favorites · ' + p.history + ' watched</div></span>' +
        '<button type="button" class="btn small send">Copy →</button></div>';
    }).join('');
  }

  // ---- drag and drop ----
  document.addEventListener('dragstart', function (e) {
    var card = e.target.closest('.card');
    if (!card) return;
    card.classList.add('dragging');
    e.dataTransfer.setData('text/plain', card.dataset.profile);
    e.dataTransfer.effectAllowed = 'copy';
  });
  document.addEventListener('dragend', function (e) {
    var card = e.target.closest('.card');
    if (card) card.classList.remove('dragging');
  });
  document.querySelectorAll('.dropzone').forEach(function (zone) {
    zone.addEventListener('dragover', function (e) {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
      zone.classList.add('over');
    });
    zone.addEventListener('dragleave', function () { zone.classList.remove('over'); });
    zone.addEventListener('drop', function (e) {
      e.preventDefault();
      zone.classList.remove('over');
      copyProfile(e.dataTransfer.getData('text/plain'), zone.dataset.side);
    });
  });

  // Touch fallback — HTML5 drag-and-drop does not work on tablets, and the
  // panel is genuinely used on one. Same operation, one tap.
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.send');
    if (!btn) return;
    var card = btn.closest('.card');
    copyProfile(card.dataset.profile, other(card.closest('.pane').dataset.side));
  });

  function copyProfile(profileId, targetSide) {
    if (!profileId) return;
    var targetAccount = selected[targetSide];
    if (!targetAccount) { showToast('Pick an account on that side first.', null); return; }

    var body = new URLSearchParams();
    body.set('csrf_token', CSRF);
    body.set('source_profile_id', profileId);
    body.set('target_account_id', targetAccount);

    fetch('api/copy_profile.php', { method: 'POST', body: body })
      .then(function (r) { return r.json(); })
      .then(function (d) {
        if (!d.success) { showToast(d.error || 'The copy failed.', null); return; }
        lastCopy = d.profile.profile_id;
        loadProfiles(targetSide);
        showToast(
          'Copied "' + d.profile.name + '" — ' + d.profile.favorites +
          ' favorites, ' + d.profile.history + ' watched.',
          function () { undoCopy(lastCopy, targetSide); }
        );
      })
      .catch(function () { showToast('The copy failed.', null); });
  }

  function undoCopy(profileId, side) {
    var body = new URLSearchParams();
    body.set('csrf_token', CSRF);
    body.set('profile_id', profileId);
    fetch('api/delete_profile.php', { method: 'POST', body: body })
      .then(function (r) { return r.json(); })
      .then(function () { loadProfiles(side); });
  }
})();
</script>

<?php require __DIR__ . '/includes/layout_end.php'; ?>
