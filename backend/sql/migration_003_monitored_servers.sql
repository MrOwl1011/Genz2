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
