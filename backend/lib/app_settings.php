<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

/**
 * A small key/value store for admin-panel settings, backed by app_settings.
 *
 * Kept deliberately dumb — strings in, strings out — because everything it
 * holds (SMTP details, alert recipients, the watcher's heartbeat) is read in
 * one or two places and validated there.
 */

/**
 * Reads several settings at once. Names with no stored row come back as ''.
 *
 * @param string[] $names
 * @return array<string, string>
 */
function settings_get(array $names): array
{
    $values = array_fill_keys($names, '');
    if ($names === []) {
        return $values;
    }
    $placeholders = implode(',', array_fill(0, count($names), '?'));
    $stmt = db()->prepare("SELECT name, value FROM app_settings WHERE name IN ($placeholders)");
    $stmt->execute(array_values($names));
    foreach ($stmt->fetchAll() as $row) {
        $values[$row['name']] = (string) $row['value'];
    }
    return $values;
}

/**
 * Writes several settings at once, creating any that do not exist yet.
 *
 * Two placeholders for the one value rather than VALUES(): VALUES() in ON
 * DUPLICATE KEY UPDATE is deprecated in MySQL 8 and gone from the newest
 * releases, and db()'s native prepares cannot bind one name twice.
 *
 * @param array<string, string> $values
 */
function settings_set(array $values): void
{
    $stmt = db()->prepare(
        'INSERT INTO app_settings (name, value) VALUES (:name, :value)
         ON DUPLICATE KEY UPDATE value = :value_again'
    );
    foreach ($values as $name => $value) {
        $stmt->execute(['name' => $name, 'value' => $value, 'value_again' => $value]);
    }
}
