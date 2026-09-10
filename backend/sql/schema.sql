-- Phase 0 schema: multi-profile + cloud sync backend for the GenZ+ IPTV app.
--
-- Design notes (see backend/README.md for the full deployment story):
--   * accounts.account_id = SHA256(normalize(server_url) + normalize(username)).
--     normalize = lowercase + trim + strip trailing slash. Password is NEVER
--     stored anywhere in this schema — it is only used transiently by
--     login.php to call the user's own Xtream panel, then discarded.
--   * profiles.profile_id is a client-generated UUID (v4), not a surrogate
--     AUTO_INCREMENT int, so a profile created offline (a later phase) never
--     needs server-side ID remapping once it syncs.
--   * favorites/history are unique on (profile_id, stream_id, stream_type) —
--     this matches how the existing Flutter app already dedups history by a
--     single id (HistoryItem.id) today, so no separate episode_id key is
--     introduced. episode_id/series_id are carried as informational columns.
--   * device_tokens stores only the SHA-256 hash of the bearer token, never
--     the raw token.
--   * profiles/favorites/history/devices/device_tokens/sync_log all cascade
--     delete from accounts, and favorites/history/sync_log cascade from
--     profiles, so deleting an account or a profile cleans up everything
--     under it in one statement (used by later admin-panel delete actions).
--
-- Only `accounts` + `devices` + `device_tokens` + `rate_limits` are actually
-- written to by Phase 0's one endpoint (login.php). `profiles`, `favorites`,
-- `history`, `sync_log`, and `admins` are created now because they're part
-- of the foundational schema, but nothing in this phase reads/writes them yet.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS accounts (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  -- account_id is now an opaque random identifier (see
  -- account_id.php's generate_anonymous_account_id()), not derived from an
  -- Xtream server_url/username the way it originally was — this backend no
  -- longer learns, stores, or validates any streaming-service credential at
  -- all. server_url/username are nullable purely so migrate_legacy.php can
  -- still look up accounts created under the old scheme on a database that
  -- already has rows from before this change; register.php never writes
  -- them for a new account. See sql/migrate_v2_anonymous_accounts.sql for
  -- the ALTER statements an already-deployed database needs to run once.
  account_id CHAR(64) NOT NULL,
  server_url VARCHAR(500) NULL,
  username VARCHAR(191) NULL,
  status ENUM('active','suspended') NOT NULL DEFAULT 'active',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at DATETIME NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_accounts_account_id (account_id),
  KEY idx_accounts_status (status),
  KEY idx_accounts_last_login (last_login_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS profiles (
  profile_id CHAR(36) NOT NULL,
  account_id CHAR(64) NOT NULL,
  name VARCHAR(60) NOT NULL,
  avatar VARCHAR(191) NOT NULL DEFAULT 'default',
  is_kids TINYINT(1) NOT NULL DEFAULT 0,
  -- Set by the admin panel's "Clear Favorites"/"Clear History" actions
  -- (never by the app itself). The client compares these against a locally
  -- stored "last applied" marker and wipes its own local favorites/history
  -- for this profile when the server's timestamp is newer — otherwise an
  -- admin clearing a profile's data had no visible effect on the device,
  -- since the normal sync merge only ever adds items, never removes ones
  -- the device already cached locally. See UserPrefsProvider.setProfileScope.
  favorites_cleared_at DATETIME NULL,
  history_cleared_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  deleted_at DATETIME NULL,
  PRIMARY KEY (profile_id),
  KEY idx_profiles_account (account_id),
  CONSTRAINT fk_profiles_account FOREIGN KEY (account_id)
    REFERENCES accounts (account_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS favorites (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  profile_id CHAR(36) NOT NULL,
  stream_id VARCHAR(64) NOT NULL,
  stream_type ENUM('movie','series','live') NOT NULL,
  title VARCHAR(255) NOT NULL,
  poster_url VARCHAR(500) NULL,
  raw_data JSON NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_favorites_profile_stream (profile_id, stream_id, stream_type),
  KEY idx_favorites_profile (profile_id),
  CONSTRAINT fk_favorites_profile FOREIGN KEY (profile_id)
    REFERENCES profiles (profile_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS history (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  profile_id CHAR(36) NOT NULL,
  stream_id VARCHAR(64) NOT NULL,
  stream_type ENUM('movie','series','live') NOT NULL,
  episode_id VARCHAR(64) NULL,
  series_id VARCHAR(64) NULL,
  title VARCHAR(255) NOT NULL,
  poster_url VARCHAR(500) NULL,
  position_seconds INT UNSIGNED NOT NULL DEFAULT 0,
  duration_seconds INT UNSIGNED NOT NULL DEFAULT 0,
  raw_data JSON NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_history_profile_stream (profile_id, stream_id, stream_type),
  KEY idx_history_profile_updated (profile_id, updated_at),
  KEY idx_history_series (profile_id, series_id),
  CONSTRAINT fk_history_profile FOREIGN KEY (profile_id)
    REFERENCES profiles (profile_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS devices (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  account_id CHAR(64) NOT NULL,
  device_id CHAR(36) NOT NULL,
  device_name VARCHAR(120) NOT NULL,
  platform VARCHAR(40) NOT NULL,
  last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_devices_account_device (account_id, device_id),
  KEY idx_devices_account (account_id),
  KEY idx_devices_last_seen (last_seen_at),
  CONSTRAINT fk_devices_account FOREIGN KEY (account_id)
    REFERENCES accounts (account_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS device_tokens (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  account_id CHAR(64) NOT NULL,
  device_id CHAR(36) NOT NULL,
  token_hash CHAR(64) NOT NULL,
  issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_device_tokens_hash (token_hash),
  KEY idx_device_tokens_account_device (account_id, device_id),
  CONSTRAINT fk_tokens_account FOREIGN KEY (account_id)
    REFERENCES accounts (account_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS admins (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  username VARCHAR(60) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at DATETIME NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_admins_username (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Append-only audit trail for future sync activity — not part of conflict
-- resolution itself, purely for admin-panel visibility/debugging later.
-- Prune rows older than ~90 days via cron once cron access is confirmed
-- (see README); no automatic pruning happens in this phase.
CREATE TABLE IF NOT EXISTS sync_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  account_id CHAR(64) NOT NULL,
  profile_id CHAR(36) NULL,
  device_id CHAR(36) NULL,
  entity_type VARCHAR(20) NOT NULL,
  operation VARCHAR(10) NOT NULL,
  entity_key VARCHAR(255) NOT NULL,
  client_updated_at DATETIME NULL,
  applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_sync_log_account_time (account_id, applied_at),
  KEY idx_sync_log_device (device_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Short-lived codes for linking a second device to an existing anonymous
-- account without either device ever exchanging identifying information —
-- see lib/pairing.php's class doc comment.
CREATE TABLE IF NOT EXISTS pairing_codes (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  code VARCHAR(8) NOT NULL,
  account_id CHAR(64) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pairing_codes_code (code),
  KEY idx_pairing_codes_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Fixed-window rate limiting (no Redis available on shared cPanel hosting).
-- bucket_key is computed by check_rate_limit() in lib/rate_limit.php as
-- sha256($identifier . ':' . $endpoint . ':' . floor(time()/$windowSeconds)).
CREATE TABLE IF NOT EXISTS rate_limits (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  bucket_key VARCHAR(191) NOT NULL,
  request_count INT UNSIGNED NOT NULL DEFAULT 1,
  window_start DATETIME NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_rate_limits_bucket (bucket_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Server status board for the admin panel (admin/servers.php).
--
-- Admin-only bookkeeping: a list of IPTV server URLs to probe. Nothing in the
-- app reads this table and no app endpoint touches it. Safe to re-run.
CREATE TABLE IF NOT EXISTS monitored_servers (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  label VARCHAR(80) NOT NULL DEFAULT '',
  url VARCHAR(500) NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
