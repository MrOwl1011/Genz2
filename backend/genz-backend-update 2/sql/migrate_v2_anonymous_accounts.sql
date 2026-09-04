-- Run this ONCE against an already-deployed database, after uploading the
-- new backend/ code, before the updated app starts calling it.
--
-- Moves the accounts table from "account_id derived from Xtream
-- credentials" to "account_id is an opaque random identifier, and no
-- credential is stored at all" — see account_id.php and register.php's doc
-- comments for the full reasoning. Existing rows are untouched: their
-- server_url/username stay exactly as they are, purely so
-- migrate_legacy.php can still find them the first time each existing
-- user's device registers under the new scheme. Nothing here deletes data;
-- migrate_legacy.php cleans up each legacy row lazily, one at a time, as
-- each real device migrates.
--
-- Safe to run more than once — every statement here is idempotent
-- (MODIFY COLUMN to the same definition, CREATE TABLE IF NOT EXISTS).

ALTER TABLE accounts
  MODIFY COLUMN server_url VARCHAR(500) NULL,
  MODIFY COLUMN username VARCHAR(191) NULL;

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
