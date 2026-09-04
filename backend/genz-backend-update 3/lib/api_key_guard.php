<?php
declare(strict_types=1);

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/json_response.php';

/**
 * Gate every endpoint (including login) behind a static API key sent via the
 * X-Api-Key header. This is NOT per-account authentication — see
 * auth_guard.php for that. It exists because login.php triggers an outbound
 * HTTP request to a caller-supplied Xtream server URL, and an otherwise
 * wide-open public endpoint that does that is worth a basic gate against
 * casual scanning/abuse (e.g. someone using this server as a URL-probing
 * proxy). Terminates the request with 401 on mismatch.
 */
function require_api_key(): void
{
    $provided = $_SERVER['HTTP_X_API_KEY'] ?? '';

    if ($provided === '' || !hash_equals(API_KEY, $provided)) {
        json_error('INVALID_API_KEY', 'Missing or invalid X-Api-Key header.', 401);
    }
}
