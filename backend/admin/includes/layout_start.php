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
    --bg: #0b0713; --surface: #170c22; --surface-elevated: #1a1128; --border: #2e1640;
    --ink: #f4f2f8; --ink-muted: #a89bb8; --brand: #7b2a8c; --brand-light: #9b4bb0;
    --accent: #12eee0; --error: #e5484d; --success: #2aa65c; --warn: #e0a02a;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: linear-gradient(160deg, #2a0e4a 0%, var(--bg) 45%, #000 100%);
    background-attachment: fixed; color: var(--ink); min-height: 100vh;
  }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  nav.topbar {
    display: flex; align-items: center; gap: 24px; padding: 14px 24px;
    background: rgba(23, 12, 34, 0.85); border-bottom: 1px solid var(--border);
    backdrop-filter: blur(8px); position: sticky; top: 0; z-index: 10; flex-wrap: wrap;
  }
  nav.topbar .brand { font-weight: 800; font-style: italic; letter-spacing: 1px; color: var(--ink); font-size: 18px; }
  nav.topbar a.navlink { color: var(--ink-muted); font-weight: 600; font-size: 14px; padding: 6px 10px; border-radius: 8px; }
  nav.topbar a.navlink:hover { color: var(--ink); text-decoration: none; background: rgba(255,255,255,0.06); }
  nav.topbar a.navlink.active { color: var(--ink); background: rgba(123,42,140,0.35); }
  nav.topbar .spacer { flex: 1; }
  main.container { max-width: 1100px; margin: 0 auto; padding: 28px 20px 60px; }
  h1 { font-size: 22px; margin: 0 0 20px; }
  h2 { font-size: 17px; margin: 28px 0 12px; }
  .card {
    background: var(--surface); border: 1px solid var(--border); border-radius: 14px;
    padding: 20px; margin-bottom: 20px;
  }
  .stat-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 14px; }
  .stat-tile { background: var(--surface); border: 1px solid var(--border); border-radius: 14px; padding: 18px; }
  .stat-tile .label { color: var(--ink-muted); font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
  .stat-tile .value { font-size: 28px; font-weight: 800; margin-top: 6px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--border); vertical-align: middle; }
  th { color: var(--ink-muted); font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; font-weight: 600; }
  tr:hover td { background: rgba(255,255,255,0.02); }
  .table-wrap { overflow-x: auto; }
  .badge { display: inline-block; padding: 3px 9px; border-radius: 999px; font-size: 11px; font-weight: 700; text-transform: uppercase; }
  .badge.active { background: rgba(42,166,92,0.18); color: var(--success); }
  .badge.suspended { background: rgba(229,72,77,0.18); color: var(--error); }
  .btn {
    display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px; border-radius: 10px;
    border: 1px solid var(--border); background: var(--surface-elevated); color: var(--ink);
    font-size: 13px; font-weight: 600; cursor: pointer; font-family: inherit;
  }
  .btn:hover { border-color: var(--brand-light); text-decoration: none; }
  .btn.primary { background: var(--brand); border-color: var(--brand); color: #fff; }
  .btn.danger { background: rgba(229,72,77,0.12); border-color: rgba(229,72,77,0.4); color: var(--error); }
  .btn.small { padding: 5px 10px; font-size: 12px; }
  form.inline { display: inline; }
  input[type=text], input[type=password], input[type=search] {
    background: var(--surface-elevated); border: 1px solid var(--border); border-radius: 10px;
    padding: 10px 12px; color: var(--ink); font-size: 14px; font-family: inherit; width: 100%;
  }
  input:focus { outline: none; border-color: var(--brand-light); }
  .search-bar { display: flex; gap: 10px; margin-bottom: 18px; flex-wrap: wrap; }
  .search-bar input[type=search] { max-width: 320px; }
  .muted { color: var(--ink-muted); }
  .flash { padding: 12px 16px; border-radius: 10px; margin-bottom: 18px; font-size: 14px; }
  .flash.success { background: rgba(42,166,92,0.15); border: 1px solid rgba(42,166,92,0.4); color: var(--success); }
  .flash.error { background: rgba(229,72,77,0.15); border: 1px solid rgba(229,72,77,0.4); color: var(--error); }
  .pagination { display: flex; gap: 8px; margin-top: 16px; }
  code { background: rgba(255,255,255,0.06); padding: 2px 6px; border-radius: 6px; font-size: 12px; }
  .login-wrap { max-width: 380px; margin: 12vh auto; padding: 0 20px; }
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
