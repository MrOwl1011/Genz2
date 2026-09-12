<?php
declare(strict_types=1);

require_once __DIR__ . '/app_settings.php';

/**
 * A minimal SMTP client for the server-monitor alerts.
 *
 * Raw sockets rather than PHPMailer: shared cPanel hosting often has no
 * Composer, and alerts need only one plain-text message to a few recipients.
 * Supports SSL (usually port 465), STARTTLS (usually 587) and plain (25), with
 * AUTH LOGIN.
 *
 * Certificates are verified. This client sends the SMTP password, so skipping
 * verification would hand it to anything able to intercept the connection.
 * That differs from the reachability probe, which sends nothing secret.
 *
 * The timeout is a config key because the two callers need different ones: an
 * admin pressing "Send test email" can wait, while the path that runs when the
 * app saves history must give up quickly.
 */

/** Setting names the Servers page reads and writes. */
const SMTP_SETTING_NAMES = [
    'smtp_host', 'smtp_port', 'smtp_secure', 'smtp_user', 'smtp_pass', 'smtp_from', 'alert_to',
];

/**
 * Splits the recipients field on commas, semicolons or whitespace and keeps
 * only valid addresses. FILTER_VALIDATE_EMAIL also rejects CR and LF, which is
 * what keeps a recipient from injecting extra SMTP commands or headers.
 *
 * @return string[]
 */
function smtp_parse_recipients(string $raw): array
{
    $parts = preg_split('/[\s,;]+/', trim($raw), -1, PREG_SPLIT_NO_EMPTY) ?: [];
    return array_values(array_unique(array_filter(
        $parts,
        static fn(string $a): bool => filter_var($a, FILTER_VALIDATE_EMAIL) !== false
    )));
}

/**
 * The saved SMTP configuration.
 *
 * @return array{host: string, port: int, secure: string, user: string, pass: string, from: string, to: string[], timeout: int}
 */
function smtp_load_config(): array
{
    $s = settings_get(SMTP_SETTING_NAMES);
    return [
        'host' => $s['smtp_host'],
        'port' => (int) $s['smtp_port'],
        'secure' => in_array($s['smtp_secure'], ['ssl', 'tls', 'none'], true) ? $s['smtp_secure'] : 'tls',
        'user' => $s['smtp_user'],
        'pass' => $s['smtp_pass'],
        'from' => $s['smtp_from'] !== '' ? $s['smtp_from'] : $s['smtp_user'],
        'to' => smtp_parse_recipients($s['alert_to']),
        'timeout' => 15,
    ];
}

/**
 * Sends one plain-text message to every configured recipient.
 *
 * @throws RuntimeException with a message fit to show an admin. It never
 *                          contains the password.
 */
function smtp_send(array $cfg, string $subject, string $body): void
{
    $host = trim($cfg['host']);
    $port = (int) $cfg['port'];
    if ($host === '' || $port < 1 || $port > 65535) {
        throw new RuntimeException('Set the SMTP host and port first.');
    }
    if ($cfg['to'] === []) {
        throw new RuntimeException('Add at least one valid alert recipient first.');
    }
    if (filter_var($cfg['from'], FILTER_VALIDATE_EMAIL) === false) {
        throw new RuntimeException('The From address is not a valid email address.');
    }

    $context = stream_context_create(['ssl' => [
        'verify_peer' => true,
        'verify_peer_name' => true,
        'peer_name' => $host,
        'SNI_enabled' => true,
    ]]);
    $timeout = max(3, (int) ($cfg['timeout'] ?? 15));
    $remote = ($cfg['secure'] === 'ssl' ? 'ssl://' : 'tcp://') . $host . ':' . $port;
    $socket = @stream_socket_client($remote, $errno, $errstr, $timeout, STREAM_CLIENT_CONNECT, $context);
    if ($socket === false) {
        $why = $errstr !== '' ? $errstr : 'no answer';
        throw new RuntimeException(
            "Could not connect to $host:$port ($why). Check the host, port and security setting."
            . ($cfg['secure'] === 'ssl' ? ' An SSL certificate problem also shows up this way.' : '')
        );
    }
    stream_set_timeout($socket, $timeout);

    try {
        smtp_expect($socket, [220]);
        $helo = preg_replace('/[^A-Za-z0-9.-]/', '', (string) gethostname()) ?: 'localhost';
        smtp_command($socket, "EHLO $helo", [250]);

        if ($cfg['secure'] === 'tls') {
            smtp_command($socket, 'STARTTLS', [220]);
            $methods = STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT | STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT;
            if (!@stream_socket_enable_crypto($socket, true, $methods)) {
                throw new RuntimeException(
                    'The encrypted connection failed. The server certificate may not match '
                    . "\"$host\", or this port does not support STARTTLS — try SSL on port 465."
                );
            }
            smtp_command($socket, "EHLO $helo", [250]);
        }

        if ($cfg['user'] !== '') {
            smtp_command($socket, 'AUTH LOGIN', [334]);
            smtp_command($socket, base64_encode($cfg['user']), [334]);
            smtp_command(
                $socket,
                base64_encode($cfg['pass']),
                [235],
                'The SMTP server rejected the username or password.'
            );
        }

        smtp_command($socket, 'MAIL FROM:<' . $cfg['from'] . '>', [250]);
        foreach ($cfg['to'] as $recipient) {
            smtp_command($socket, "RCPT TO:<$recipient>", [250, 251]);
        }
        smtp_command($socket, 'DATA', [354]);

        $domain = substr((string) strrchr($cfg['from'], '@'), 1) ?: 'localhost';
        $headers = [
            'From: GENz+ Monitor <' . $cfg['from'] . '>',
            'To: ' . implode(', ', $cfg['to']),
            // Encoded-word, so a server name in Arabic survives, and so no
            // label can smuggle a line break into the header block.
            'Subject: =?UTF-8?B?' . base64_encode($subject) . '?=',
            'Date: ' . date('r'),
            'Message-ID: <' . bin2hex(random_bytes(12)) . '@' . $domain . '>',
            'MIME-Version: 1.0',
            'Content-Type: text/plain; charset=UTF-8',
            // Base64 body: no line can start with a dot, so no dot-stuffing,
            // and non-ASCII text needs no further care.
            'Content-Transfer-Encoding: base64',
        ];
        fwrite($socket, implode("\r\n", $headers) . "\r\n\r\n" . chunk_split(base64_encode($body)) . ".\r\n");
        smtp_expect($socket, [250]);
        @fwrite($socket, "QUIT\r\n");
    } finally {
        fclose($socket);
    }
}

/** Reads one reply, which may span several "250-" continuation lines. */
function smtp_read($socket): string
{
    $reply = '';
    while (($line = fgets($socket, 1024)) !== false) {
        $reply .= $line;
        if (strlen($line) < 4 || $line[3] === ' ') {
            break;
        }
    }
    if ($reply === '') {
        $meta = stream_get_meta_data($socket);
        throw new RuntimeException(
            ($meta['timed_out'] ?? false)
                ? 'The SMTP server stopped responding.'
                : 'The SMTP server closed the connection.'
        );
    }
    return $reply;
}

/** @param int[] $codes */
function smtp_expect($socket, array $codes, ?string $failure = null): string
{
    $reply = smtp_read($socket);
    if (!in_array((int) substr($reply, 0, 3), $codes, true)) {
        $lines = preg_split('/\r?\n/', trim($reply)) ?: [$reply];
        throw new RuntimeException($failure ?? ('The SMTP server said: ' . end($lines)));
    }
    return $reply;
}

/** @param int[] $codes */
function smtp_command($socket, string $line, array $codes, ?string $failure = null): string
{
    fwrite($socket, $line . "\r\n");
    return smtp_expect($socket, $codes, $failure);
}
