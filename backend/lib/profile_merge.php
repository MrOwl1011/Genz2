<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/../config.php';

/**
 * Folds every non-deleted profile still under $oldAccountId into
 * $targetAccountId, oldest-created first.
 *
 * Lives here rather than inside a single endpoint because three callers
 * need it: account/join.php (pairing codes, on its way out), and
 * account/merge.php (which serves both the one-time migration from the old
 * anonymous accounts and the ongoing "the user's IPTV password changed"
 * case). Do not inline a second copy of this — the SQL below has two
 * non-obvious fixes in it that were found the hard way against a live
 * database, and a divergent copy would silently lose them.
 *
 * Two distinct outcomes depending on whether the name already exists on
 * the target account:
 *
 *   - Name collision ("Kids" exists on both sides): this is the same
 *     viewer on two devices, not two different people who happened to pick
 *     the same name — so their data is combined into the ONE existing
 *     target profile rather than kept as two separately-named copies. Every
 *     favorite either side had ends up on the merged profile; for a
 *     history row both sides have (same stream_id+stream_type), whichever
 *     side's `updated_at` is more recent wins, so neither device's more
 *     recent watch progress gets clobbered by the other's older entry. The
 *     now-empty old profile is soft-deleted (deleted_at).
 *   - No collision: the profile moves across as-is (a plain account_id
 *     repoint), up to whatever room MAX_PROFILES_PER_ACCOUNT leaves. A
 *     merge never costs a profile slot (the target's count doesn't
 *     change), so the cap only ever applies to this non-colliding case.
 *
 * Returns [merged_count, left_behind_count]. left_behind_count is only
 * ever nonzero when the target account was already at
 * MAX_PROFILES_PER_ACCOUNT and a non-colliding profile had nowhere to go;
 * it's left untouched on the old account, recoverable later via the admin
 * panel's profile copy if it ever matters.
 *
 * Caller owns the transaction — this runs no BEGIN/COMMIT of its own so a
 * caller can do other work atomically alongside it.
 */
function merge_profiles_into_target(PDO $pdo, string $oldAccountId, string $targetAccountId): array
{
    $oldProfilesStmt = $pdo->prepare(
        'SELECT profile_id, name FROM profiles
         WHERE account_id = :account_id AND deleted_at IS NULL
         ORDER BY created_at ASC'
    );
    $oldProfilesStmt->execute(['account_id' => $oldAccountId]);
    $oldProfiles = $oldProfilesStmt->fetchAll();

    if (empty($oldProfiles)) {
        return [0, 0];
    }

    $targetProfilesStmt = $pdo->prepare(
        'SELECT profile_id, name FROM profiles WHERE account_id = :account_id AND deleted_at IS NULL'
    );
    $targetProfilesStmt->execute(['account_id' => $targetAccountId]);
    $targetProfileIdByName = [];
    foreach ($targetProfilesStmt->fetchAll() as $row) {
        $targetProfileIdByName[$row['name']] = $row['profile_id'];
    }

    $mergedCount = 0;
    $leftBehindCount = 0;

    $moveProfileStmt = $pdo->prepare(
        'UPDATE profiles SET account_id = :target_account_id, updated_at = NOW()
         WHERE profile_id = :profile_id'
    );

    // Favorites carry no meaningful "which side is newer" signal (it's a
    // boolean, not a progress value) — ON DUPLICATE KEY UPDATE here is a
    // true no-op, just letting the INSERT silently skip rows the target
    // profile already has instead of erroring on the unique key.
    //
    // Aliasing the source as `src` alone isn't enough: this INSERT selects
    // from the very table it inserts into, and it was confirmed live
    // against the real database that MySQL still refuses to resolve a bare
    // `id` in ON DUPLICATE KEY UPDATE ("Column 'id' in UPDATE is
    // ambiguous", SQLSTATE 23000) unless the updated column is *also*
    // explicitly qualified with the target table's own name.
    $mergeFavoritesStmt = $pdo->prepare(
        'INSERT INTO favorites (profile_id, stream_id, stream_type, title, poster_url, raw_data, created_at, updated_at)
         SELECT :target_profile_id, stream_id, stream_type, title, poster_url, raw_data, created_at, updated_at
         FROM favorites AS src WHERE src.profile_id = :old_profile_id
         ON DUPLICATE KEY UPDATE favorites.id = favorites.id'
    );
    // History DOES carry a meaningful signal (position_seconds is real
    // watch progress) — keep whichever side was touched more recently.
    // Same self-referencing INSERT...SELECT as favorites above, same fix:
    // every bare column reference below is qualified with `history.` so it
    // unambiguously means "the existing target row", not "the source row
    // being selected from the same table".
    $mergeHistoryStmt = $pdo->prepare(
        'INSERT INTO history (profile_id, stream_id, stream_type, episode_id, series_id, title, poster_url, position_seconds, duration_seconds, raw_data, updated_at)
         SELECT :target_profile_id, stream_id, stream_type, episode_id, series_id, title, poster_url, position_seconds, duration_seconds, raw_data, updated_at
         FROM history AS src WHERE src.profile_id = :old_profile_id
         ON DUPLICATE KEY UPDATE
           position_seconds = IF(VALUES(updated_at) > history.updated_at, VALUES(position_seconds), history.position_seconds),
           duration_seconds = IF(VALUES(updated_at) > history.updated_at, VALUES(duration_seconds), history.duration_seconds),
           episode_id = IF(VALUES(updated_at) > history.updated_at, VALUES(episode_id), history.episode_id),
           series_id = IF(VALUES(updated_at) > history.updated_at, VALUES(series_id), history.series_id),
           raw_data = IF(VALUES(updated_at) > history.updated_at, VALUES(raw_data), history.raw_data),
           updated_at = GREATEST(history.updated_at, VALUES(updated_at))'
    );
    $deleteFavoritesStmt = $pdo->prepare('DELETE FROM favorites WHERE profile_id = :profile_id');
    $deleteHistoryStmt = $pdo->prepare('DELETE FROM history WHERE profile_id = :profile_id');
    $softDeleteProfileStmt = $pdo->prepare(
        'UPDATE profiles SET deleted_at = NOW(), updated_at = NOW() WHERE profile_id = :profile_id'
    );

    foreach ($oldProfiles as $profile) {
        $name = (string) $profile['name'];
        $oldProfileId = $profile['profile_id'];

        if (isset($targetProfileIdByName[$name])) {
            $targetProfileId = $targetProfileIdByName[$name];
            $mergeFavoritesStmt->execute([
                'target_profile_id' => $targetProfileId,
                'old_profile_id' => $oldProfileId,
            ]);
            $mergeHistoryStmt->execute([
                'target_profile_id' => $targetProfileId,
                'old_profile_id' => $oldProfileId,
            ]);
            $deleteFavoritesStmt->execute(['profile_id' => $oldProfileId]);
            $deleteHistoryStmt->execute(['profile_id' => $oldProfileId]);
            $softDeleteProfileStmt->execute(['profile_id' => $oldProfileId]);
            $mergedCount++;
            continue;
        }

        if (count($targetProfileIdByName) >= MAX_PROFILES_PER_ACCOUNT) {
            $leftBehindCount++;
            continue;
        }

        $moveProfileStmt->execute([
            'target_account_id' => $targetAccountId,
            'profile_id' => $oldProfileId,
        ]);
        $targetProfileIdByName[$name] = $oldProfileId;
        $mergedCount++;
    }

    return [$mergedCount, $leftBehindCount];
}
