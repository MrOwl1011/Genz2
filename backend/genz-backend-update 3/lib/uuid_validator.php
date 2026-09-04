<?php
declare(strict_types=1);

/**
 * profile_id is always client-generated (never minted server-side — see
 * schema.sql's note on why), so every endpoint that accepts one needs to
 * validate its shape before trusting it as a primary key value.
 */
function is_valid_uuid(string $value): bool
{
    return (bool) preg_match(
        '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
        $value
    );
}
