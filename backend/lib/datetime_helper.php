<?php
declare(strict_types=1);

require_once __DIR__ . '/json_response.php';

/**
 * Parses a client-supplied timestamp (ISO-8601, e.g. what Dart's
 * DateTime.toIso8601String() produces) into MySQL DATETIME format, in UTC.
 * This is the timestamp compared for last-write-wins conflict resolution —
 * see profiles/create.php and profiles/update.php — so a malformed or
 * missing value is a hard 400, not something to default silently.
 */
function parse_client_datetime(string $value): string
{
    $dt = date_create($value);
    if ($dt === false) {
        json_error('INVALID_BODY', 'updated_at must be a valid ISO-8601 timestamp.', 400);
    }
    $dt->setTimezone(new DateTimeZone('UTC'));
    return $dt->format('Y-m-d H:i:s');
}
