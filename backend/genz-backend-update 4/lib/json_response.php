<?php
declare(strict_types=1);

/**
 * Standardized success envelope: {"success": true, "data": ..., "error": null}.
 * Always terminates the request — callers should treat this as their return.
 */
function json_success($data = null, int $httpStatus = 200): void
{
    http_response_code($httpStatus);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'success' => true,
        'data' => $data,
        'error' => null,
    ], JSON_UNESCAPED_SLASHES);
    exit;
}

/**
 * Standardized error envelope: {"success": false, "data": null, "error": {code, message}}.
 * $code is a short machine-readable string (e.g. "INVALID_CREDENTIALS",
 * "RATE_LIMITED") for the Flutter client to branch on; $message is
 * human-readable and safe to show directly to the user.
 */
function json_error(string $code, string $message, int $httpStatus = 400): void
{
    http_response_code($httpStatus);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'success' => false,
        'data' => null,
        'error' => [
            'code' => $code,
            'message' => $message,
        ],
    ], JSON_UNESCAPED_SLASHES);
    exit;
}

/**
 * Reads and JSON-decodes the raw request body. Every endpoint in this API is
 * POST + application/json, no exceptions — reject anything else up front
 * rather than let a malformed body surface as a confusing downstream error.
 */
function read_json_body(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '') {
        json_error('INVALID_BODY', 'Request body must be JSON.', 400);
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        json_error('INVALID_BODY', 'Request body must be a JSON object.', 400);
    }

    return $decoded;
}

// Installed once, the first time any endpoint requires this file (every
// endpoint does). Guarantees the client always gets back valid JSON — never
// a raw PHP warning/fatal-error HTML page — even if something unexpected
// throws or a stray notice fires somewhere in the request. Without this, an
// uncaught error would print outside the JSON envelope (or replace it
// entirely) and silently break every client-side json_decode() call.
set_exception_handler(function (Throwable $e): void {
    error_log('[Unhandled exception] ' . $e->getMessage() . ' in ' . $e->getFile() . ':' . $e->getLine());
    json_error('INTERNAL_ERROR', 'Something went wrong. Please try again.', 500);
});

set_error_handler(function (int $severity, string $message, string $file = '', int $line = 0): bool {
    error_log("[PHP warning/notice] $message in $file:$line");
    return true; // suppress PHP's own handler, which would otherwise echo this into the response body
});
