<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/app_settings.php';
require_once __DIR__ . '/smtp_mailer.php';

/**
 * Emails the admin when a watched profile starts watching something new.
 *
 * Called from api/history/save.php, which the app hits roughly every 30
 * seconds during playback — so this only ever runs for a genuinely new
 * history row, and only for a profile an admin has chosen to watch. Both
 * conditions are checked here, cheaply, before anything slower happens.
 *
 * Nothing in here may break a history save: the app's sync must not fail, or
 * slow down, because a mail server is unhappy. Every failure is swallowed and
 * written to notification_log for the Notifications page to show.
 */

/** How long the mail step may take on the app's request path. */
const WATCH_MAIL_TIMEOUT_SECONDS = 6;

/**
 * True if this profile is being watched. One indexed primary-key lookup, so
 * it is safe to call on every new history row.
 */
function profile_is_watched(string $profileId): bool
{
    try {
        $stmt = db()->prepare('SELECT 1 FROM profile_watches WHERE profile_id = :id');
        $stmt->execute(['id' => $profileId]);
        return $stmt->fetchColumn() !== false;
    } catch (Throwable $e) {
        // profile_watches is created by migration_005. Until it is run, this
        // feature is simply off rather than an error on the app's sync path.
        return false;
    }
}

/**
 * Sends the notification and records the attempt.
 *
 * Call only after confirming the row was newly inserted; see save.php.
 */
function notify_new_history(string $profileId, string $title, string $streamType): void
{
    $pdo = db();

    $stmt = $pdo->prepare(
        'SELECT p.name AS profile_name, p.account_id, a.username
           FROM profiles p
           LEFT JOIN accounts a ON a.account_id = p.account_id
          WHERE p.profile_id = :id'
    );
    $stmt->execute(['id' => $profileId]);
    $profile = $stmt->fetch();
    if ($profile === false) {
        return;
    }

    $profileName = (string) $profile['profile_name'];
    $kind = match ($streamType) {
        'movie' => 'a movie',
        'series' => 'a series',
        'live' => 'a live channel',
        default => 'something',
    };
    $who = ($profile['username'] ?? '') !== ''
        ? (string) $profile['username']
        : substr((string) $profile['account_id'], 0, 12) . '…';
    $when = (new DateTime('now', new DateTimeZone('+03:00')))->format('Y-m-d H:i') . ' (GMT+3)';

    $sent = 0;
    $error = null;
    try {
        $cfg = smtp_load_config();
        $cfg['timeout'] = WATCH_MAIL_TIMEOUT_SECONDS;
        smtp_send(
            $cfg,
            "[GENz+] $profileName started watching: $title",
            "$profileName started watching $kind.\n\n"
            . "Title:      $title\n"
            . "Profile:    $profileName\n"
            . "Account:    $who\n"
            . "Started:    $when\n\n"
            . "You are getting this because this profile is on the watch list on the\n"
            . "Notifications page of the GENz+ admin panel.\n"
        );
        $sent = 1;
    } catch (Throwable $e) {
        $error = mb_substr($e->getMessage(), 0, 255);
    }

    try {
        $pdo->prepare(
            'INSERT INTO notification_log (profile_id, profile_name, title, stream_type, sent, error)
             VALUES (:profile_id, :profile_name, :title, :stream_type, :sent, :error)'
        )->execute([
            'profile_id' => $profileId,
            'profile_name' => mb_substr($profileName, 0, 60),
            'title' => mb_substr($title, 0, 255),
            'stream_type' => $streamType,
            'sent' => $sent,
            'error' => $error,
        ]);
    } catch (Throwable $e) {
        error_log('[profile_watch] could not write notification_log: ' . $e->getMessage());
    }
}
