<?php
declare(strict_types=1);
// Expects $pageTitle (string) and optionally $activeNav ('dashboard'|'accounts')
// to be set by the including page before this file is required.
$activeNav = $activeNav ?? '';
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="robots" content="noindex, nofollow">
<title><?= html_escape($pageTitle ?? 'Admin') ?> · GenZ+ Admin</title>
<style>
  :root {
    --bg: #0b0713; --surface: #170c22; --surface-elevated: #1c1029; --border: #2e1640;
    --border-soft: #241332;
    --ink: #f4f2f8; --ink-muted: #a89bb8; --brand: #7b2a8c; --brand-light: #a855c7;
    --accent: #12eee0; --error: #e5484d; --success: #2aa65c; --warn: #e0a02a;
    --shadow-card: 0 8px 24px rgba(0,0,0,0.28), 0 1px 0 rgba(255,255,255,0.03) inset;
    --shadow-pop: 0 12px 32px rgba(123,42,140,0.22);
    --radius: 16px;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background:
      radial-gradient(1100px 520px at 15% -10%, rgba(123,42,140,0.35), transparent 60%),
      radial-gradient(900px 480px at 100% 0%, rgba(18,238,224,0.08), transparent 55%),
      linear-gradient(160deg, #26103f 0%, var(--bg) 45%, #000 100%);
    background-attachment: fixed; color: var(--ink); min-height: 100vh;
    -webkit-font-smoothing: antialiased;
  }
  a { color: var(--accent); text-decoration: none; transition: opacity 0.15s ease; }
  a:hover { opacity: 0.8; }
  nav.topbar {
    display: flex; align-items: center; gap: 22px; padding: 16px 26px;
    background: rgba(16, 9, 24, 0.72); border-bottom: 1px solid var(--border);
    backdrop-filter: blur(14px) saturate(140%); -webkit-backdrop-filter: blur(14px) saturate(140%);
    position: sticky; top: 0; z-index: 10; flex-wrap: wrap;
  }
  nav.topbar .brand {
    font-weight: 800; font-style: italic; letter-spacing: 0.5px; font-size: 19px;
    background: linear-gradient(135deg, #fff 10%, var(--brand-light) 100%);
    -webkit-background-clip: text; background-clip: text; color: transparent;
  }
  nav.topbar a.navlink {
    color: var(--ink-muted); font-weight: 600; font-size: 14px; padding: 7px 12px; border-radius: 9px;
    transition: background 0.15s ease, color 0.15s ease;
  }
  nav.topbar a.navlink:hover { color: var(--ink); background: rgba(255,255,255,0.06); opacity: 1; }
  nav.topbar a.navlink.active { color: #fff; background: linear-gradient(135deg, var(--brand), #5c1f6b); box-shadow: 0 2px 10px rgba(123,42,140,0.4); }
  nav.topbar .spacer { flex: 1; }
  main.container { max-width: 1140px; margin: 0 auto; padding: 32px 20px 60px; }
  h1 { font-size: 24px; margin: 0 0 22px; font-weight: 800; letter-spacing: -0.2px; }
  h2 { font-size: 16px; margin: 32px 0 14px; font-weight: 700; color: var(--ink); letter-spacing: 0.2px; }
  .card {
    background: linear-gradient(180deg, var(--surface) 0%, #140a1e 100%);
    border: 1px solid var(--border); border-radius: var(--radius);
    padding: 22px; margin-bottom: 20px; box-shadow: var(--shadow-card);
  }
  .stat-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 14px; }
  .stat-tile {
    position: relative; overflow: hidden;
    background: linear-gradient(180deg, var(--surface) 0%, #140a1e 100%);
    border: 1px solid var(--border); border-radius: var(--radius); padding: 18px 20px;
    box-shadow: var(--shadow-card); transition: transform 0.18s ease, border-color 0.18s ease;
  }
  .stat-tile:hover { transform: translateY(-2px); border-color: var(--brand-light); }
  .stat-tile::before {
    content: ''; position: absolute; top: 0; left: 0; right: 0; height: 3px;
    background: linear-gradient(90deg, var(--brand), var(--accent));
  }
  .stat-tile .label { color: var(--ink-muted); font-size: 11.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.6px; }
  .stat-tile .value { font-size: 30px; font-weight: 800; margin-top: 8px; letter-spacing: -0.5px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { text-align: left; padding: 12px 14px; border-bottom: 1px solid var(--border-soft); vertical-align: middle; }
  th { color: var(--ink-muted); font-size: 11.5px; text-transform: uppercase; letter-spacing: 0.6px; font-weight: 700; }
  tbody tr { transition: background 0.12s ease; }
  tbody tr:hover td { background: rgba(255,255,255,0.03); }
  tbody tr:last-child td { border-bottom: none; }
  .table-wrap { overflow-x: auto; border-radius: 10px; }
  .badge {
    display: inline-flex; align-items: center; gap: 5px; padding: 4px 11px; border-radius: 999px;
    font-size: 10.5px; font-weight: 800; text-transform: uppercase; letter-spacing: 0.4px;
  }
  .badge::before { content: ''; width: 6px; height: 6px; border-radius: 50%; background: currentColor; }
  .badge.active { background: rgba(42,166,92,0.16); color: var(--success); border: 1px solid rgba(42,166,92,0.3); }
  .badge.suspended { background: rgba(229,72,77,0.16); color: var(--error); border: 1px solid rgba(229,72,77,0.3); }
  .btn {
    display: inline-flex; align-items: center; gap: 6px; padding: 9px 16px; border-radius: 10px;
    border: 1px solid var(--border); background: var(--surface-elevated); color: var(--ink);
    font-size: 13px; font-weight: 600; cursor: pointer; font-family: inherit;
    transition: transform 0.12s ease, border-color 0.15s ease, box-shadow 0.15s ease, background 0.15s ease;
  }
  .btn:hover { border-color: var(--brand-light); text-decoration: none; transform: translateY(-1px); }
  .btn:active { transform: translateY(0); }
  .btn.primary {
    background: linear-gradient(135deg, var(--brand), #5c1f6b); border-color: var(--brand); color: #fff;
    box-shadow: 0 4px 14px rgba(123,42,140,0.35);
  }
  .btn.primary:hover { box-shadow: 0 6px 18px rgba(123,42,140,0.5); }
  .btn.danger { background: rgba(229,72,77,0.1); border-color: rgba(229,72,77,0.35); color: var(--error); }
  .btn.danger:hover { background: rgba(229,72,77,0.18); border-color: var(--error); }
  .btn.small { padding: 6px 11px; font-size: 12px; border-radius: 8px; }
  form.inline { display: inline-block; margin-right: 6px; }
  input[type=text], input[type=password], input[type=search], select {
    background: var(--surface-elevated); border: 1px solid var(--border); border-radius: 10px;
    padding: 10px 13px; color: var(--ink); font-size: 14px; font-family: inherit; width: 100%;
    transition: border-color 0.15s ease, box-shadow 0.15s ease;
  }
  input:focus, select:focus { outline: none; border-color: var(--brand-light); box-shadow: 0 0 0 3px rgba(168,85,199,0.18); }
  .search-bar { display: flex; gap: 10px; margin-bottom: 18px; flex-wrap: wrap; }
  .search-bar input[type=search] { max-width: 320px; }
  .muted { color: var(--ink-muted); }
  .flash {
    padding: 13px 18px; border-radius: 12px; margin-bottom: 18px; font-size: 14px; font-weight: 500;
    box-shadow: var(--shadow-card);
  }
  .flash.success { background: rgba(42,166,92,0.12); border: 1px solid rgba(42,166,92,0.35); color: #6bd99a; }
  .flash.error { background: rgba(229,72,77,0.12); border: 1px solid rgba(229,72,77,0.35); color: #f19093; }
  .pagination { display: flex; gap: 8px; margin-top: 18px; }
  code { background: rgba(255,255,255,0.07); padding: 3px 7px; border-radius: 6px; font-size: 12px; }
  .login-wrap { max-width: 380px; margin: 12vh auto; padding: 0 20px; }
  .login-wrap .card { box-shadow: var(--shadow-card), var(--shadow-pop); }
  .login-wrap h1 { text-align: center; }
  .field { margin-bottom: 14px; }
  .field label { display: block; font-size: 13px; color: var(--ink-muted); margin-bottom: 6px; font-weight: 600; }
</style>
</head>
<body>
<?php if (is_admin_logged_in()): ?>
<nav class="topbar">
  <span class="brand">GenZ+ Admin</span>
  <a class="navlink <?= $activeNav === 'dashboard' ? 'active' : '' ?>" href="index.php">Dashboard</a>
  <a class="navlink <?= $activeNav === 'accounts' ? 'active' : '' ?>" href="accounts.php">Accounts</a>
  <span class="spacer"></span>
  <a class="navlink" href="logout.php">Log out</a>
</nav>
<?php endif; ?>
<main class="container">
