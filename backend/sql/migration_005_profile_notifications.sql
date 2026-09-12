-- Email notifications when a watched profile starts something new, and
-- removal of the background server-watching tables.
--
-- Replaces migration_004: server watching is gone, so server_monitors is
-- dropped, while app_settings stays (it holds the SMTP settings). Plain
-- CREATE TABLE IF NOT EXISTS, so it pastes into phpMyAdmin and is safe to
-- run again. Admin-only; the app reads none of these.

-- Left over from server watching, which has been removed.
DROP TABLE IF EXISTS server_monitors;

-- SMTP settings and other panel settings. Created by migration_004 as well;
-- kept here so a fresh database gets it too.
CREATE TABLE IF NOT EXISTS app_settings (
  name VARCHAR(64) NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The profiles being watched. One row per profile; removing the profile
-- removes the watch with it.
CREATE TABLE IF NOT EXISTS profile_watches (
  profile_id CHAR(36) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (profile_id),
  CONSTRAINT fk_profile_watches_profile
    FOREIGN KEY (profile_id) REFERENCES profiles (profile_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- What was sent, and what failed. Shown on the Notifications page so a
-- missing email can be told apart from a notification that never fired.
-- No foreign key: the log should survive a profile being deleted.
CREATE TABLE IF NOT EXISTS notification_log (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  profile_id CHAR(36) NOT NULL,
  profile_name VARCHAR(60) NOT NULL DEFAULT '',
  title VARCHAR(255) NOT NULL,
  stream_type VARCHAR(10) NOT NULL DEFAULT '',
  sent TINYINT(1) NOT NULL DEFAULT 0,
  error VARCHAR(255) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_notification_log_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
