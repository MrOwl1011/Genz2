<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

/**
 * Short-lived codes that let a second (or third...) device join an existing
 * anonymous account without either device ever exchanging Xtream
 * credentials or any other identifying information — the whole point of the
 * anonymous account_id scheme (see account_id.php) is that the sync backend
 * never learns what service a user has, so linking devices has to happen
 * through a channel that carries none of that either.
 *
 * A code is deliberately multi-use within its window rather than single-use:
 * the common case is pairing several devices (phone, tablet, TV box) off one
 * code shown once in Settings, and a 15-minute window is short enough that
 * multi-use doesn't meaningfully widen the attack surface — a stranger would
 * need to both see the code on someone's screen and use it within 15
 * minutes.
 */
const PAIRING_CODE_TTL_SECONDS = 900;
const PAIRING_CODE_LENGTH = 4;

// Excludes 0/O/1/I/L — a code is read off one screen and typed on another,
// and those are exactly the characters people mistype from a glance.
const PAIRING_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

function generate_pairing_code(string $accountId): array
{
    $pdo = db();

    // At 4 chars from a 32-symbol alphabet there are only ~1M possible
    // codes — collisions are no longer astronomically unlikely the way they
    // were at 8, so this retry loop is now doing real work, not just
    // removing a theoretical failure mode. The bigger consequence of a
    // short, human-typeable code is guessability: join.php rate-limits
    // attempts specifically because of this (see its doc comment) — do not
    // shorten this further without re-checking that limit is still enough.
    for ($attempt = 0; $attempt < 5; $attempt++) {
        $code = '';
        for ($i = 0; $i < PAIRING_CODE_LENGTH; $i++) {
            $code .= PAIRING_CODE_ALPHABET[random_int(0, strlen(PAIRING_CODE_ALPHABET) - 1)];
        }

        $expiresAt = date('Y-m-d H:i:s', time() + PAIRING_CODE_TTL_SECONDS);

        try {
            $stmt = $pdo->prepare(
                'INSERT INTO pairing_codes (code, account_id, expires_at)
                 VALUES (:code, :account_id, :expires_at)'
            );
            $stmt->execute([
                'code' => $code,
                'account_id' => $accountId,
                'expires_at' => $expiresAt,
            ]);
            return ['code' => $code, 'expires_at' => $expiresAt];
        } catch (PDOException $e) {
            // 23000 = integrity constraint violation (the UNIQUE key on
            // `code`) — retry with a freshly rolled code. Anything else is a
            // real error and should propagate.
            if ($e->getCode() !== '23000') {
                throw $e;
            }
        }
    }

    throw new RuntimeException('Could not generate a unique pairing code.');
}

/**
 * Resolves a code to the account_id it was issued for, or null if it does
 * not exist or has expired. Does not consume the code — see the class doc
 * comment for why codes are multi-use within their window.
 */
function resolve_pairing_code(string $code): ?string
{
    $pdo = db();
    $stmt = $pdo->prepare(
        'SELECT account_id FROM pairing_codes
         WHERE code = :code AND expires_at > NOW()'
    );
    $stmt->execute(['code' => strtoupper(trim($code))]);
    $accountId = $stmt->fetchColumn();
    return $accountId === false ? null : (string) $accountId;
}
