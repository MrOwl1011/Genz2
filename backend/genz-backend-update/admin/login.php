<?php
declare(strict_types=1);

require_once __DIR__ . '/includes/bootstrap.php';

if (is_admin_logged_in()) {
    header('Location: index.php');
    exit;
}

$error = null;
$justCreated = isset($_GET['created']);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_valid_csrf();

    $username = trim((string) ($_POST['username'] ?? ''));
    $password = (string) ($_POST['password'] ?? '');

    // Same fixed-window table the app API uses (backend/lib/rate_limit.php),
    // keyed by IP — blunts brute-forcing the admin password.
    require_once __DIR__ . '/../lib/rate_limit.php';
    if (!check_rate_limit(client_ip(), 'admin_login', 10, 3600)) {
        $error = 'Too many login attempts. Please try again later.';
    } else {
        $stmt = db()->prepare('SELECT id, password_hash FROM admins WHERE username = :username');
        $stmt->execute(['username' => $username]);
        $admin = $stmt->fetch();

        if ($admin === false || !password_verify($password, $admin['password_hash'])) {
            $error = 'Invalid username or password.';
        } else {
            session_regenerate_id(true);
            $_SESSION['admin_id'] = $admin['id'];
            $_SESSION['admin_last_activity'] = time();
            unset($_SESSION['csrf_token']); // fresh token for the new session

            $update = db()->prepare('UPDATE admins SET last_login_at = NOW() WHERE id = :id');
            $update->execute(['id' => $admin['id']]);

            header('Location: index.php');
            exit;
        }
    }
}

require __DIR__ . '/includes/layout_start.php';
?>
<div class="login-wrap">
  <div class="card">
    <h1>Admin Login</h1>
    <?php if ($justCreated): ?>
      <div class="flash success">Admin account created. Log in below.</div>
    <?php endif; ?>
    <?php if ($error !== null): ?>
      <div class="flash error"><?= html_escape($error) ?></div>
    <?php endif; ?>
    <form method="POST">
      <input type="hidden" name="csrf_token" value="<?= html_escape(csrf_token()) ?>">
      <div class="field">
        <label for="username">Username</label>
        <input type="text" id="username" name="username" required autofocus>
      </div>
      <div class="field">
        <label for="password">Password</label>
        <input type="password" id="password" name="password" required>
      </div>
      <button type="submit" class="btn primary" style="width:100%;justify-content:center;">Log In</button>
    </form>
  </div>
</div>
<?php require __DIR__ . '/includes/layout_end.php'; ?>
