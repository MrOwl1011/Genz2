-- Background watching and email alerts for the admin Servers page.
--
-- Needs migration_003 (monitored_servers) to have run first. Plain CREATE
-- TABLE IF NOT EXISTS only — no ALTERs and no stored procedures — so it pastes
-- straight into phpMyAdmin, runs on MySQL and MariaDB alike, and is safe to
-- run again. Admin-only; nothing in the app reads either table.

-- One row per watched server. Kept out of monitored_servers so adding this
-- feature needed no ALTER on an existing table.
CREATE TABLE IF NOT EXISTS server_monitors (
  server_id INT UNSIGNED NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 0,
  interval_seconds INT UNSIGNED NOT NULL DEFAULT 300,
  last_up TINYINT(1) NULL,
  last_code SMALLINT UNSIGNED NULL,
  last_ms INT UNSIGNED NULL,
  last_error VARCHAR(255) NULL,
  last_checked_at DATETIME NULL,
  next_check_at DATETIME NULL,
  status_since DATETIME NULL,
  PRIMARY KEY (server_id),
  KEY idx_server_monitors_due (enabled, next_check_at),
  CONSTRAINT fk_server_monitors_server
    FOREIGN KEY (server_id) REFERENCES monitored_servers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Small key/value store for panel settings: SMTP details, alert
-- recipients, and the watcher's heartbeat.
CREATE TABLE IF NOT EXISTS app_settings (
  name VARCHAR(64) NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
