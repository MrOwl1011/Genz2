<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

// One-time bootstrap for creating the very first admin account — there's no
// CLI/SSH access assumed on shared cPanel hosting, so this is the only way
// to seed the `admins` table initially. Permanently refuses to run again
// the moment any admin row exists, so it can't be used as a standing
// backdoor — delete this file after first use if you want to be extra safe,
// but it's inert either way once an admin exists.
$existingCount = (int) db()->query('SELECT COUNT(*) FROM admins')->fetchColumn();
if ($existingCount > 0) {
    require __DIR__ . '/includes/layout_start.php';
    ?>
    <div class="login-wrap">
      <div class="card">
        <h1>Setup already completed</h1>
        <p class="muted">An admin account already exists. Go to <a href="login.php">login</a> instead.</p>
      </div>
    </div>
    <?php
    require __DIR__ . '/includes/layout_end.php';
    exit;
}

$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_valid_csrf();

    $username = trim((string) ($_POST['username'] ?? ''));
    $password = (string) ($_POST['password'] ?? '');
    $confirm = (string) ($_POST['confirm'] ?? '');

    if ($username === '' || mb_strlen($username) > 60) {
        $error = 'Username is required and must be 60 characters or fewer.';
    } elseif (strlen($password) < 10) {
        $error = 'Password must be at least 10 characters.';
    } elseif ($password !== $confirm) {
        $error = 'Passwords do not match.';
    } else {
        // Re-check under the same guard right before inserting — closes the
        // (tiny) race window between the count check above and this insert.
        $recheck = (int) db()->query('SELECT COUNT(*) FROM admins')->fetchColumn();
        if ($recheck > 0) {
            $error = 'Setup was already completed. Please refresh and log in instead.';
        } else {
            $stmt = db()->prepare('INSERT INTO admins (username, password_hash) VALUES (:username, :password_hash)');
            $stmt->execute([
                'username' => $username,
                'password_hash' => password_hash($password, PASSWORD_DEFAULT),
            ]);
            header('Location: login.php?created=1');
            exit;
        }
    }
}

require __DIR__ . '/includes/layout_start.php';
?>
<div class="login-wrap">
  <div class="card">
    <h1>Create the first admin account</h1>
    <p class="muted">This page only works once — it disables itself as soon as any admin account exists.</p>
    <?php if ($error !== null): ?>
      <div class="flash error"><?= html_escape($error) ?></div>
    <?php endif; ?>
    <form method="POST">
      <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
      <div class="field">
        <label for="username">Username</label>
        <input type="text" id="username" name="username" required maxlength="60" autofocus>
      </div>
      <div class="field">
        <label for="password">Password (10+ characters)</label>
        <input type="password" id="password" name="password" required minlength="10">
      </div>
      <div class="field">
        <label for="confirm">Confirm password</label>
        <input type="password" id="confirm" name="confirm" required minlength="10">
      </div>
      <button type="submit" class="btn primary" style="width:100%;justify-content:center;">Create Admin Account</button>
    </form>
  </div>
</div>
<?php require __DIR__ . '/includes/layout_end.php'; ?>
