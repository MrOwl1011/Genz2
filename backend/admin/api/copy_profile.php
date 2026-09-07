<?php
declare(strict_types=1);

require_once __DIR__ . '/../includes/bootstrap.php';
require_once __DIR__ . '/../../lib/db.php';
require_once __DIR__ . '/../../config.php';

/**
 * Copies ONE profile from one account to another, with its favorites and
 * its watch history. Backs the drag-and-drop screen in
 * admin/profile_transfer.php.
 *
 * Three rules this endpoint is built around, in order of importance:
 *
 *   1. It only ever ADDS. The source profile is never modified, moved or
 *      deleted, and no existing profile on the target is ever touched. A
 *      mis-drop cannot lose data — the worst case is an extra profile,
 *      which the caller can delete.
 *   2. One profile per call. There is deliberately no batch parameter, so
 *      there is no shape of request that could copy a whole account's
 *      profiles at once by accident.
 *   3. It is a snapshot, not a link. The new profile gets a fresh UUID and
 *      no relationship to the original is recorded anywhere; the two
 *      diverge from this moment on. Nothing about it is synchronized.
 *
 * On a name collision it appends "(copy)" rather than merging into the
 * existing same-named profile: merging would rewrite that profile's watch
 * progress, which rule 1 forbids.
 *
 * Responds JSON. Session-authenticated as an admin, not with the app's
 * bearer tokens.
 */
require_admin_login();

header('Content-Type: application/json; charset=utf-8');

/** Emits a JSON error and stops. */
function copy_error(string $message, int $status = 400): never
{
    http_response_code($status);
    echo json_encode(['success' => false, 'error' => $message]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    copy_error('POST required.', 405);
}
require_valid_csrf();

$sourceProfileId = trim((string) ($_POST['source_profile_id'] ?? ''));
$targetAccountId = trim((string) ($_POST['target_account_id'] ?? ''));

if ($sourceProfileId === '' || $targetAccountId === '') {
    copy_error('source_profile_id and target_account_id are both required.');
}

$pdo = db();

$sourceStmt = $pdo->prepare(
    'SELECT profile_id, account_id, name, avatar, is_kids
     FROM profiles WHERE profile_id = :profile_id AND deleted_at IS NULL'
);
$sourceStmt->execute(['profile_id' => $sourceProfileId]);
$source = $sourceStmt->fetch();
if ($source === false) {
    copy_error('That profile no longer exists.', 404);
}

$targetStmt = $pdo->prepare('SELECT 1 FROM accounts WHERE account_id = :account_id');
$targetStmt->execute(['account_id' => $targetAccountId]);
if ($targetStmt->fetchColumn() === false) {
    copy_error('That target account no longer exists.', 404);
}

if ((string) $source['account_id'] === $targetAccountId) {
    copy_error('That profile is already on this account.', 409);
}

// Existing names on the target, both to enforce the cap and to pick a
// non-colliding name below.
$existingStmt = $pdo->prepare(
    'SELECT name FROM profiles WHERE account_id = :account_id AND deleted_at IS NULL'
);
$existingStmt->execute(['account_id' => $targetAccountId]);
$existingNames = array_map(static fn(array $r): string => (string) $r['name'], $existingStmt->fetchAll());

if (count($existingNames) >= MAX_PROFILES_PER_ACCOUNT) {
    copy_error(
        'That account already has the maximum of ' . MAX_PROFILES_PER_ACCOUNT . ' profiles.',
        409
    );
}

// "Kids" -> "Kids (copy)" -> "Kids (copy 2)" ... Never merges, never
// overwrites; see rule 1 in the doc comment.
$name = (string) $source['name'];
if (in_array($name, $existingNames, true)) {
    $candidate = $name . ' (copy)';
    $n = 2;
    while (in_array($candidate, $existingNames, true)) {
        $candidate = $name . ' (copy ' . $n . ')';
        $n++;
    }
    $name = $candidate;
}
// profiles.name is VARCHAR(60) — a long original plus a suffix could
// overflow it, which would be a hard SQL error rather than a graceful one.
if (mb_strlen($name) > 60) {
    $name = mb_substr($name, 0, 60);
}

$newProfileId = sprintf(
    '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x',
    random_int(0, 0xffff), random_int(0, 0xffff),
    random_int(0, 0xffff),
    random_int(0, 0x0fff),
    random_int(0, 0x3fff) | 0x8000,
    random_int(0, 0xffff), random_int(0, 0xffff), random_int(0, 0xffff)
);

$pdo->beginTransaction();
try {
    $insertProfile = $pdo->prepare(
        'INSERT INTO profiles (profile_id, account_id, name, avatar, is_kids)
         VALUES (:profile_id, :account_id, :name, :avatar, :is_kids)'
    );
    $insertProfile->execute([
        'profile_id' => $newProfileId,
        'account_id' => $targetAccountId,
        'name' => $name,
        'avatar' => $source['avatar'],
        'is_kids' => (int) $source['is_kids'],
    ]);

    // Straight copies into a brand-new profile_id, so unlike the merge in
    // lib/profile_merge.php there is no possibility of a unique-key
    // collision and no ON DUPLICATE KEY clause is needed.
    $copyFavorites = $pdo->prepare(
        'INSERT INTO favorites (profile_id, stream_id, stream_type, title, poster_url, raw_data, created_at, updated_at)
         SELECT :new_profile_id, stream_id, stream_type, title, poster_url, raw_data, created_at, updated_at
         FROM favorites WHERE profile_id = :source_profile_id'
    );
    $copyFavorites->execute([
        'new_profile_id' => $newProfileId,
        'source_profile_id' => $sourceProfileId,
    ]);
    $favoritesCopied = $copyFavorites->rowCount();

    $copyHistory = $pdo->prepare(
        'INSERT INTO history (profile_id, stream_id, stream_type, episode_id, series_id, title, poster_url, position_seconds, duration_seconds, raw_data, updated_at)
         SELECT :new_profile_id, stream_id, stream_type, episode_id, series_id, title, poster_url, position_seconds, duration_seconds, raw_data, updated_at
         FROM history WHERE profile_id = :source_profile_id'
    );
    $copyHistory->execute([
        'new_profile_id' => $newProfileId,
        'source_profile_id' => $sourceProfileId,
    ]);
    $historyCopied = $copyHistory->rowCount();

    $pdo->commit();
} catch (Throwable $e) {
    $pdo->rollBack();
    copy_error('The copy failed and nothing was changed.', 500);
}

echo json_encode([
    'success' => true,
    'profile' => [
        'profile_id' => $newProfileId,
        'name' => $name,
        'avatar' => $source['avatar'],
        'is_kids' => (bool) $source['is_kids'],
        'favorites' => $favoritesCopied,
        'history' => $historyCopied,
    ],
]);
