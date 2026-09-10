<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../../lib/server_probe.php';

/**
 * Probes one saved server on demand, for the live column on the Servers page.
 *
 * Takes an id, never a URL, so it only ever reaches what an admin already
 * saved. What "up" means lives in probe_server(), which the cron watcher shares.
 *
 * Deliberately leaves server_monitors alone. Opening the page must not move a
 * watched server's alert state or send an email; only the watcher does that.
 */
require_admin_login();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'POST required.']);
    exit;
}
require_valid_csrf();

$stmt = db()->prepare('SELECT url FROM monitored_servers WHERE id = :id');
$stmt->execute(['id' => (int) ($_POST['id'] ?? 0)]);
$url = $stmt->fetchColumn();

if ($url === false) {
    http_response_code(404);
    echo json_encode(['success' => false, 'error' => 'That server is no longer listed.']);
    exit;
}

echo json_encode(['success' => true] + probe_server((string) $url));
