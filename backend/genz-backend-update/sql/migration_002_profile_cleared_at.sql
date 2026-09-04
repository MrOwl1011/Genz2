-- Run this once against the already-deployed database via phpMyAdmin (or
-- any MySQL client) — schema.sql alone only affects a fresh install, it
-- cannot alter a table that already exists.
--
-- Adds the two columns the admin panel's "Clear Favorites"/"Clear History"
-- actions use to actually notify the app, instead of only deleting rows on
-- the server while every device's local cache stays untouched.

ALTER TABLE profiles
  ADD COLUMN favorites_cleared_at DATETIME NULL AFTER is_kids,
  ADD COLUMN history_cleared_at DATETIME NULL AFTER favorites_cleared_at;
