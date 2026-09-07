<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../../lib/db.php';

/**
 * Soft-deletes one profile. Exists so a copy made by drag-and-drop in
 * profile_transfer.php can be undone immediately — a drop writes real
 * rows, and an accidental one shouldn't be permanent.
 *
 * Soft delete (deleted_at) rather than a hard DELETE, matching how the
 * admin panel already removes profiles elsewhere: the profile disappears
 * from every listing and from the app, but its favorites and history rows
 * stay recoverable if a deletion turns out to have been the mistake.
 */
require_admin_login();

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'POST required.']);
    exit;
}
require_valid_csrf();

$profileId = trim((string) ($_POST['profile_id'] ?? ''));
if ($profileId === '') {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'profile_id is required.']);
    exit;
}

$stmt = db()->prepare(
    'UPDATE profiles SET deleted_at = NOW(), updated_at = NOW()
     WHERE profile_id = :profile_id AND deleted_at IS NULL'
);
$stmt->execute(['profile_id' => $profileId]);

if ($stmt->rowCount() === 0) {
    http_response_code(404);
    echo json_encode(['success' => false, 'error' => 'That profile was already removed.']);
    exit;
}

echo json_encode(['success' => true]);
