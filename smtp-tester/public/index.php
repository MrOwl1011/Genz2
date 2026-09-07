<?php
/**
 * SMTP Email Tester — Standalone tool
 * Uses raw PHP sockets to test SMTP connections, no external dependencies.
 */

// Handle API requests
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json');
    
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        echo json_encode(['success' => false, 'error' => 'Invalid JSON input']);
        exit;
    }
    
    $action = $input['action'] ?? 'send';
    $host   = trim($input['host'] ?? '');
    $port   = intval($input['port'] ?? 587);
    $user   = trim($input['user'] ?? '');
    $pass   = $input['pass'] ?? '';
    $secure = $input['secure'] ?? 'tls';
    $from   = trim($input['fromEmail'] ?? '') ?: $user;
    $to     = trim($input['toEmail'] ?? '');
    $subject = $input['subject'] ?? '🧪 SMTP Test Email — Connection Successful!';
    
    $steps = [];
    
    if (!$host || !$port || !$user || !$pass) {
        echo json_encode([
            'success' => false,
            'steps' => [['step' => 'Missing required fields: host, port, user, pass', 'status' => 'error']],
            'error' => 'Missing required fields'
        ]);
        exit;
    }
    
    if ($action === 'send' && !$to) {
        echo json_encode([
            'success' => false,
            'steps' => [['step' => 'Missing "Send To" email address', 'status' => 'error']],
            'error' => 'Missing recipient email'
        ]);
        exit;
    }
    
    // Attempt SMTP connection
    try {
        $steps[] = ['step' => "Connecting to $host:$port...", 'status' => 'ok'];
        
        $errno = 0;
        $errstr = '';
        $timeout = 15;
        
        // Determine stream context and prefix
        if ($secure === 'ssl') {
            $context = stream_context_create([
                'ssl' => [
                    'verify_peer' => false,
                    'verify_peer_name' => false,
                    'allow_self_signed' => true
                ]
            ]);
            $socket = @stream_socket_client(
                "ssl://$host:$port",
                $errno, $errstr, $timeout,
                STREAM_CLIENT_CONNECT,
                $context
            );
        } else {
            $socket = @stream_socket_client(
                "tcp://$host:$port",
                $errno, $errstr, $timeout,
                STREAM_CLIENT_CONNECT
            );
        }
        
        if (!$socket) {
            throw new Exception("Connection failed: $errstr (Error code: $errno)");
        }
        
        stream_set_timeout($socket, $timeout);
        
        // Read greeting
        $greeting = readResponse($socket);
        if (substr($greeting, 0, 3) !== '220') {
            throw new Exception("Unexpected greeting: $greeting");
        }
        $steps[] = ['step' => "✅ Connected! Server says: " . trim($greeting), 'status' => 'ok'];
        
        // EHLO
        sendCommand($socket, "EHLO localhost");
        $ehloResp = readResponse($socket);
        if (substr($ehloResp, 0, 3) !== '250') {
            throw new Exception("EHLO failed: $ehloResp");
        }
        $steps[] = ['step' => '✅ EHLO accepted', 'status' => 'ok'];
        
        // STARTTLS if needed
        if ($secure === 'tls') {
            sendCommand($socket, "STARTTLS");
            $tlsResp = readResponse($socket);
            if (substr($tlsResp, 0, 3) !== '220') {
                throw new Exception("STARTTLS failed: $tlsResp");
            }
            
            $cryptoResult = stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT | STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT);
            if (!$cryptoResult) {
                throw new Exception("TLS handshake failed. The server may not support TLS on this port.");
            }
            $steps[] = ['step' => '✅ STARTTLS encryption enabled', 'status' => 'ok'];
            
            // Re-EHLO after STARTTLS
            sendCommand($socket, "EHLO localhost");
            readResponse($socket);
        }
        
        // AUTH LOGIN
        sendCommand($socket, "AUTH LOGIN");
        $authResp = readResponse($socket);
        if (substr($authResp, 0, 3) !== '334') {
            throw new Exception("AUTH LOGIN not supported: $authResp");
        }
        
        // Send username
        sendCommand($socket, base64_encode($user));
        $userResp = readResponse($socket);
        if (substr($userResp, 0, 3) !== '334') {
            throw new Exception("Username rejected: $userResp");
        }
        
        // Send password
        sendCommand($socket, base64_encode($pass));
        $passResp = readResponse($socket);
        if (substr($passResp, 0, 3) !== '235') {
            $errMsg = trim($passResp);
            throw new Exception("Authentication failed: $errMsg");
        }
        $steps[] = ['step' => '✅ Authentication successful!', 'status' => 'ok'];
        
        // If verify-only, stop here
        if ($action === 'verify') {
            sendCommand($socket, "QUIT");
            @readResponse($socket);
            fclose($socket);
            
            $steps[] = ['step' => 'SMTP connection verified — your credentials are correct!', 'status' => 'ok'];
            $steps[] = ['step' => 'No email was sent. Use "Send Test Email" to send one.', 'status' => 'info'];
            echo json_encode(['success' => true, 'steps' => $steps]);
            exit;
        }
        
        // MAIL FROM
        sendCommand($socket, "MAIL FROM:<$from>");
        $mailResp = readResponse($socket);
        if (substr($mailResp, 0, 3) !== '250') {
            throw new Exception("MAIL FROM rejected: $mailResp");
        }
        $steps[] = ['step' => "✅ Sender accepted: $from", 'status' => 'ok'];
        
        // RCPT TO
        sendCommand($socket, "RCPT TO:<$to>");
        $rcptResp = readResponse($socket);
        if (substr($rcptResp, 0, 3) !== '250') {
            throw new Exception("RCPT TO rejected: $rcptResp");
        }
        $steps[] = ['step' => "✅ Recipient accepted: $to", 'status' => 'ok'];
        
        // DATA
        sendCommand($socket, "DATA");
        $dataResp = readResponse($socket);
        if (substr($dataResp, 0, 3) !== '354') {
            throw new Exception("DATA command failed: $dataResp");
        }
        
        // Build email
        $date = date('r');
        $messageId = '<' . uniqid('smtp-tester-', true) . '@' . parse_url($host, PHP_URL_HOST) . '>';
        $boundary = '----=_Part_' . uniqid();
        
        $htmlBody = buildTestEmailHtml($host, $port, $secure, $from, $date);
        $textBody = "SMTP Test Email\n\nYour email configuration is working correctly!\n\nHost: $host\nPort: $port\nSecurity: $secure\nFrom: $from\nSent at: $date";
        
        $headers = "Date: $date\r\n";
        $headers .= "From: $from\r\n";
        $headers .= "To: $to\r\n";
        $headers .= "Subject: $subject\r\n";
        $headers .= "Message-ID: $messageId\r\n";
        $headers .= "MIME-Version: 1.0\r\n";
        $headers .= "Content-Type: multipart/alternative; boundary=\"$boundary\"\r\n";
        $headers .= "\r\n";
        $headers .= "--$boundary\r\n";
        $headers .= "Content-Type: text/plain; charset=UTF-8\r\n";
        $headers .= "Content-Transfer-Encoding: 7bit\r\n";
        $headers .= "\r\n";
        $headers .= $textBody . "\r\n";
        $headers .= "\r\n--$boundary\r\n";
        $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
        $headers .= "Content-Transfer-Encoding: 7bit\r\n";
        $headers .= "\r\n";
        $headers .= $htmlBody . "\r\n";
        $headers .= "\r\n--$boundary--\r\n";
        $headers .= ".";
        
        sendCommand($socket, $headers);
        $sendResp = readResponse($socket);
        if (substr($sendResp, 0, 3) !== '250') {
            throw new Exception("Message sending failed: $sendResp");
        }
        
        $steps[] = ['step' => '✅ Email sent successfully!', 'status' => 'ok'];
        $steps[] = ['step' => 'Server response: ' . trim($sendResp), 'status' => 'info'];
        
        // QUIT
        sendCommand($socket, "QUIT");
        @readResponse($socket);
        fclose($socket);
        
        echo json_encode(['success' => true, 'steps' => $steps, 'messageId' => $messageId]);
        
    } catch (Exception $e) {
        if (isset($socket) && is_resource($socket)) {
            @fclose($socket);
        }
        
        $errMsg = $e->getMessage();
        $steps[] = ['step' => "❌ Error: $errMsg", 'status' => 'error'];
        
        // Diagnosis
        $diagnosis = getDiagnosis($errMsg, $errno ?? 0);
        if ($diagnosis) {
            $steps[] = ['step' => $diagnosis, 'status' => 'diagnosis'];
        }
        
        echo json_encode(['success' => false, 'steps' => $steps, 'error' => $errMsg]);
    }
    exit;
}

function sendCommand($socket, $command) {
    fwrite($socket, $command . "\r\n");
}

function readResponse($socket) {
    $response = '';
    $endTime = time() + 15;
    while (time() < $endTime) {
        $line = fgets($socket, 4096);
        if ($line === false) break;
        $response .= $line;
        // Check if this is the last line of a multi-line response
        if (isset($line[3]) && $line[3] === ' ') break;
        if (strlen($line) < 4) break;
    }
    return $response;
}

function getDiagnosis($errMsg, $errno) {
    $errLower = strtolower($errMsg);
    if (str_contains($errLower, 'connection refused') || $errno == 111) {
        return '🔍 The server refused the connection. Check the host and port. Make sure firewalls are not blocking the connection.';
    }
    if (str_contains($errLower, 'could not resolve') || str_contains($errLower, 'getaddrinfo')) {
        return '🔍 The hostname could not be resolved. Double-check the SMTP host address.';
    }
    if (str_contains($errLower, 'timed out') || str_contains($errLower, 'timeout')) {
        return '🔍 Connection timed out. The server might be down, or the port might be wrong. Try port 465 with SSL or port 587 with TLS.';
    }
    if (str_contains($errLower, 'authentication') || str_contains($errLower, 'auth') || str_contains($errLower, '535')) {
        return '🔍 Authentication failed. Double-check your username and password. Some providers require an "App Password" instead of your regular password.';
    }
    if (str_contains($errLower, 'certificate') || str_contains($errLower, 'ssl') || str_contains($errLower, 'tls handshake')) {
        return '🔍 SSL/TLS error. Try switching between TLS (port 587) and SSL (port 465). The server certificate might be self-signed.';
    }
    if (str_contains($errLower, 'starttls')) {
        return '🔍 STARTTLS negotiation failed. The server may not support STARTTLS on this port. Try port 465 with SSL instead.';
    }
    return '🔍 Check your SMTP settings and try again. Make sure the credentials are correct and the server is reachable from your network.';
}

function buildTestEmailHtml($host, $port, $secure, $from, $date) {
    $secLabel = match($secure) {
        'tls' => 'STARTTLS',
        'ssl' => 'SSL/TLS',
        default => 'None'
    };
    return <<<HTML
<div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 30px; background: linear-gradient(135deg, #0f0f1a 0%, #1a1a2e 100%); border-radius: 16px;">
  <div style="text-align: center; padding: 20px 0;">
    <h1 style="color: #a78bfa; margin: 0; font-size: 28px;">✅ SMTP Test Successful</h1>
    <p style="color: #94a3b8; margin-top: 8px; font-size: 16px;">Your email configuration is working correctly!</p>
  </div>
  <div style="background: rgba(167, 139, 250, 0.1); border: 1px solid rgba(167, 139, 250, 0.2); border-radius: 12px; padding: 20px; margin: 20px 0;">
    <h3 style="color: #c4b5fd; margin: 0 0 12px 0; font-size: 16px;">Connection Details</h3>
    <table style="width: 100%; color: #cbd5e1; font-size: 14px;">
      <tr><td style="padding: 6px 0; color: #94a3b8;">SMTP Host:</td><td style="padding: 6px 0; font-weight: 600;">$host</td></tr>
      <tr><td style="padding: 6px 0; color: #94a3b8;">Port:</td><td style="padding: 6px 0; font-weight: 600;">$port</td></tr>
      <tr><td style="padding: 6px 0; color: #94a3b8;">Security:</td><td style="padding: 6px 0; font-weight: 600;">$secLabel</td></tr>
      <tr><td style="padding: 6px 0; color: #94a3b8;">From:</td><td style="padding: 6px 0; font-weight: 600;">$from</td></tr>
      <tr><td style="padding: 6px 0; color: #94a3b8;">Sent at:</td><td style="padding: 6px 0; font-weight: 600;">$date</td></tr>
    </table>
  </div>
  <p style="color: #64748b; font-size: 12px; text-align: center; margin-top: 20px;">Sent by SMTP Tester Tool</p>
</div>
HTML;
}

// Serve the HTML page
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SMTP Email Tester</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --bg-primary: #06060e;
      --bg-secondary: #0d0d1a;
      --bg-card: rgba(15, 15, 30, 0.7);
      --bg-input: rgba(20, 20, 40, 0.8);
      --border: rgba(100, 80, 200, 0.15);
      --border-focus: rgba(139, 92, 246, 0.5);
      --text-primary: #e2e8f0;
      --text-secondary: #94a3b8;
      --text-muted: #64748b;
      --accent: #8b5cf6;
      --accent-glow: rgba(139, 92, 246, 0.3);
      --success: #34d399;
      --success-bg: rgba(52, 211, 153, 0.08);
      --error: #f87171;
      --error-bg: rgba(248, 113, 113, 0.08);
      --warning: #fbbf24;
      --info: #60a5fa;
    }

    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      background: var(--bg-primary);
      color: var(--text-primary);
      min-height: 100vh;
      overflow-x: hidden;
    }

    .bg-gradient {
      position: fixed; inset: 0; z-index: 0; overflow: hidden;
    }
    .bg-gradient::before {
      content: ''; position: absolute; width: 600px; height: 600px;
      background: radial-gradient(circle, rgba(139, 92, 246, 0.08) 0%, transparent 70%);
      top: -200px; left: -100px; animation: float1 20s ease-in-out infinite;
    }
    .bg-gradient::after {
      content: ''; position: absolute; width: 500px; height: 500px;
      background: radial-gradient(circle, rgba(59, 130, 246, 0.06) 0%, transparent 70%);
      bottom: -200px; right: -100px; animation: float2 25s ease-in-out infinite;
    }
    @keyframes float1 { 0%, 100% { transform: translate(0, 0); } 50% { transform: translate(100px, 80px); } }
    @keyframes float2 { 0%, 100% { transform: translate(0, 0); } 50% { transform: translate(-80px, -60px); } }

    .container {
      position: relative; z-index: 1; max-width: 720px; margin: 0 auto; padding: 40px 20px 60px;
    }

    .header { text-align: center; margin-bottom: 40px; }
    .header-icon {
      display: inline-flex; align-items: center; justify-content: center;
      width: 72px; height: 72px; border-radius: 20px;
      background: linear-gradient(135deg, rgba(139, 92, 246, 0.15) 0%, rgba(59, 130, 246, 0.1) 100%);
      border: 1px solid rgba(139, 92, 246, 0.2); font-size: 32px; margin-bottom: 20px;
      animation: pulseIcon 3s ease-in-out infinite;
    }
    @keyframes pulseIcon {
      0%, 100% { box-shadow: 0 0 0 0 rgba(139, 92, 246, 0.2); }
      50% { box-shadow: 0 0 30px 10px rgba(139, 92, 246, 0.1); }
    }
    .header h1 {
      font-size: 32px; font-weight: 800;
      background: linear-gradient(135deg, #c4b5fd 0%, #818cf8 50%, #60a5fa 100%);
      -webkit-background-clip: text; -webkit-text-fill-color: transparent;
      background-clip: text; letter-spacing: -0.5px;
    }
    .header p { color: var(--text-secondary); font-size: 15px; margin-top: 8px; }

    .card {
      background: var(--bg-card); backdrop-filter: blur(20px);
      border: 1px solid var(--border); border-radius: 20px;
      padding: 32px; margin-bottom: 24px; transition: border-color 0.3s;
    }
    .card:hover { border-color: rgba(100, 80, 200, 0.25); }
    .card-title {
      font-size: 16px; font-weight: 700; color: var(--text-primary);
      margin-bottom: 6px; display: flex; align-items: center; gap: 10px;
    }
    .card-title .icon { font-size: 18px; }
    .card-subtitle { font-size: 13px; color: var(--text-muted); margin-bottom: 24px; }

    .form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
    .form-row.single { grid-template-columns: 1fr; }
    .form-group { margin-bottom: 18px; }
    .form-group label {
      display: block; font-size: 13px; font-weight: 600;
      color: var(--text-secondary); margin-bottom: 6px; letter-spacing: 0.3px;
    }
    .form-group label .required { color: var(--accent); margin-left: 2px; }

    input, select {
      width: 100%; padding: 12px 16px; background: var(--bg-input);
      border: 1px solid var(--border); border-radius: 12px;
      color: var(--text-primary); font-family: 'Inter', sans-serif;
      font-size: 14px; transition: all 0.25s; outline: none;
    }
    input::placeholder { color: var(--text-muted); }
    input:focus, select:focus {
      border-color: var(--border-focus);
      box-shadow: 0 0 0 3px rgba(139, 92, 246, 0.1), 0 0 20px rgba(139, 92, 246, 0.05);
    }
    select {
      cursor: pointer; appearance: none;
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' fill='%2394a3b8' viewBox='0 0 16 16'%3E%3Cpath d='M4.646 6.354l3 3a.5.5 0 00.708 0l3-3a.5.5 0 00-.708-.708L8 8.293 5.354 5.646a.5.5 0 10-.708.708z'/%3E%3C/svg%3E");
      background-repeat: no-repeat; background-position: right 14px center; padding-right: 40px;
    }
    select option { background: #1a1a2e; color: var(--text-primary); }

    .input-wrapper { position: relative; }
    .input-wrapper .toggle-pass {
      position: absolute; right: 12px; top: 50%; transform: translateY(-50%);
      background: none; border: none; color: var(--text-muted);
      cursor: pointer; font-size: 16px; padding: 4px; transition: color 0.2s;
    }
    .input-wrapper .toggle-pass:hover { color: var(--text-secondary); }
    .input-wrapper input { padding-right: 44px; }

    .btn-group { display: flex; gap: 12px; margin-top: 8px; }
    .btn {
      display: inline-flex; align-items: center; justify-content: center; gap: 8px;
      padding: 14px 28px; border: none; border-radius: 14px;
      font-family: 'Inter', sans-serif; font-size: 14px; font-weight: 600;
      cursor: pointer; transition: all 0.3s; position: relative; overflow: hidden;
    }
    .btn-primary {
      flex: 1; background: linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%);
      color: #fff; box-shadow: 0 4px 15px rgba(139, 92, 246, 0.3);
    }
    .btn-primary:hover:not(:disabled) {
      transform: translateY(-2px); box-shadow: 0 8px 25px rgba(139, 92, 246, 0.4);
    }
    .btn-primary:active:not(:disabled) { transform: translateY(0); }
    .btn-secondary {
      background: rgba(139, 92, 246, 0.1); color: var(--accent);
      border: 1px solid rgba(139, 92, 246, 0.2);
    }
    .btn-secondary:hover:not(:disabled) {
      background: rgba(139, 92, 246, 0.15); border-color: rgba(139, 92, 246, 0.3);
    }
    .btn:disabled { opacity: 0.6; cursor: not-allowed; }

    .spinner {
      width: 18px; height: 18px; border: 2px solid rgba(255,255,255,0.2);
      border-top-color: #fff; border-radius: 50%;
      animation: spin 0.7s linear infinite; display: none;
    }
    .btn.loading .spinner { display: block; }
    .btn.loading .btn-text { display: none; }
    @keyframes spin { to { transform: rotate(360deg); } }

    .results { display: none; margin-top: 24px; animation: slideUp 0.4s ease-out; }
    .results.visible { display: block; }
    @keyframes slideUp {
      from { opacity: 0; transform: translateY(20px); }
      to { opacity: 1; transform: translateY(0); }
    }

    .result-header {
      display: flex; align-items: center; gap: 12px;
      padding: 16px 20px; border-radius: 14px 14px 0 0; font-weight: 700; font-size: 15px;
    }
    .result-header.success {
      background: var(--success-bg); border: 1px solid rgba(52, 211, 153, 0.15);
      border-bottom: none; color: var(--success);
    }
    .result-header.error {
      background: var(--error-bg); border: 1px solid rgba(248, 113, 113, 0.15);
      border-bottom: none; color: var(--error);
    }

    .result-steps {
      background: rgba(10, 10, 20, 0.6); border: 1px solid var(--border);
      border-top: none; border-radius: 0 0 14px 14px; padding: 16px 20px;
    }
    .step {
      display: flex; align-items: flex-start; gap: 10px;
      padding: 10px 0; font-size: 13px; line-height: 1.5;
      border-bottom: 1px solid rgba(100, 80, 200, 0.06); animation: fadeIn 0.3s ease-out;
    }
    .step:last-child { border-bottom: none; }
    @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }

    .step-icon {
      flex-shrink: 0; width: 22px; height: 22px; border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      font-size: 11px; margin-top: 1px;
    }
    .step-icon.ok { background: rgba(52, 211, 153, 0.15); color: var(--success); }
    .step-icon.error { background: rgba(248, 113, 113, 0.15); color: var(--error); }
    .step-icon.info { background: rgba(96, 165, 250, 0.15); color: var(--info); }
    .step-icon.diagnosis { background: rgba(251, 191, 36, 0.15); color: var(--warning); }
    .step-text { color: var(--text-secondary); word-break: break-word; }
    .step-text.error { color: var(--error); }

    .presets { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 20px; }
    .preset-btn {
      padding: 6px 14px; background: rgba(139, 92, 246, 0.06);
      border: 1px solid rgba(139, 92, 246, 0.12); border-radius: 8px;
      color: var(--text-secondary); font-size: 12px; font-weight: 500;
      cursor: pointer; transition: all 0.2s; font-family: 'Inter', sans-serif;
    }
    .preset-btn:hover {
      background: rgba(139, 92, 246, 0.12); border-color: rgba(139, 92, 246, 0.25);
      color: var(--text-primary);
    }

    .divider {
      height: 1px;
      background: linear-gradient(90deg, transparent, var(--border), transparent);
      margin: 6px 0 22px;
    }

    .footer { text-align: center; color: var(--text-muted); font-size: 12px; margin-top: 32px; }

    .toast {
      position: fixed; top: 20px; right: 20px; padding: 14px 20px;
      border-radius: 12px; font-size: 13px; font-weight: 500; z-index: 1000;
      animation: toastIn 0.3s ease-out; display: none;
      max-width: 400px; box-shadow: 0 8px 30px rgba(0,0,0,0.4);
    }
    .toast.visible { display: flex; align-items: center; gap: 10px; }
    .toast.success { background: rgba(20, 50, 40, 0.95); border: 1px solid rgba(52, 211, 153, 0.3); color: var(--success); }
    .toast.error { background: rgba(50, 20, 20, 0.95); border: 1px solid rgba(248, 113, 113, 0.3); color: var(--error); }
    @keyframes toastIn {
      from { opacity: 0; transform: translateX(40px); }
      to { opacity: 1; transform: translateX(0); }
    }

    @media (max-width: 600px) {
      .form-row { grid-template-columns: 1fr; }
      .container { padding: 24px 16px 40px; }
      .card { padding: 24px; }
      .header h1 { font-size: 26px; }
      .btn-group { flex-direction: column; }
    }
  </style>
</head>
<body>
  <div class="bg-gradient"></div>
  <div class="container">
    <div class="header">
      <div class="header-icon">📧</div>
      <h1>SMTP Email Tester</h1>
      <p>Test your SMTP credentials and send a test email to verify delivery</p>
    </div>

    <div class="card">
      <div class="card-title"><span class="icon">🔐</span> SMTP Credentials</div>
      <div class="card-subtitle">Enter the outgoing mail server details from your cPanel</div>

      <div class="presets">
        <button class="preset-btn" onclick="applyPreset('cpanel')">cPanel Default</button>
        <button class="preset-btn" onclick="applyPreset('gmail')">Gmail</button>
        <button class="preset-btn" onclick="applyPreset('outlook')">Outlook</button>
        <button class="preset-btn" onclick="applyPreset('zoho')">Zoho</button>
      </div>

      <form id="smtpForm">
        <div class="form-row">
          <div class="form-group">
            <label>SMTP Host <span class="required">*</span></label>
            <input type="text" id="host" placeholder="mail.yourdomain.com" required>
          </div>
          <div class="form-group">
            <label>Port <span class="required">*</span></label>
            <input type="number" id="port" placeholder="587" value="587" required>
          </div>
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Username / Email <span class="required">*</span></label>
            <input type="text" id="user" placeholder="orders@yourdomain.com" required>
          </div>
          <div class="form-group">
            <label>Password <span class="required">*</span></label>
            <div class="input-wrapper">
              <input type="password" id="pass" placeholder="Your mailbox password" required>
              <button type="button" class="toggle-pass" onclick="togglePassword()">👁</button>
            </div>
          </div>
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Security</label>
            <select id="secure">
              <option value="tls">STARTTLS (Port 587)</option>
              <option value="ssl">SSL/TLS (Port 465)</option>
              <option value="none">None (Port 25)</option>
            </select>
          </div>
          <div class="form-group">
            <label>From Email</label>
            <input type="email" id="fromEmail" placeholder="Same as username if empty">
          </div>
        </div>

        <div class="divider"></div>

        <div class="form-row single">
          <div class="form-group">
            <label>Send Test Email To <span class="required">*</span></label>
            <input type="email" id="toEmail" placeholder="your-personal@email.com" required>
          </div>
        </div>
        <div class="form-row">
          <div class="form-group">
            <label>Subject</label>
            <input type="text" id="subject" placeholder="🧪 SMTP Test Email">
          </div>
        </div>

        <div class="btn-group">
          <button type="button" class="btn btn-secondary" onclick="verifyOnly()" id="verifyBtn">
            <span class="spinner"></span>
            <span class="btn-text">🔍 Verify Only</span>
          </button>
          <button type="submit" class="btn btn-primary" id="sendBtn">
            <span class="spinner"></span>
            <span class="btn-text">🚀 Send Test Email</span>
          </button>
        </div>
      </form>
    </div>

    <div class="results" id="results">
      <div class="result-header" id="resultHeader">
        <span class="result-icon" id="resultIcon"></span>
        <span id="resultTitle"></span>
      </div>
      <div class="result-steps" id="resultSteps"></div>
    </div>

    <div class="footer">
      🔒 This tool runs locally on your machine · Your credentials are never stored
    </div>
  </div>

  <div class="toast" id="toast">
    <span id="toastIcon"></span>
    <span id="toastText"></span>
  </div>

  <script>
    const form = document.getElementById('smtpForm');
    const results = document.getElementById('results');
    const sendBtn = document.getElementById('sendBtn');
    const verifyBtn = document.getElementById('verifyBtn');

    function applyPreset(provider) {
      const presets = {
        cpanel: { host: 'mail.', port: 587, secure: 'tls' },
        gmail: { host: 'smtp.gmail.com', port: 587, secure: 'tls' },
        outlook: { host: 'smtp-mail.outlook.com', port: 587, secure: 'tls' },
        zoho: { host: 'smtp.zoho.com', port: 587, secure: 'tls' }
      };
      const p = presets[provider];
      if (p) {
        document.getElementById('host').value = p.host;
        document.getElementById('port').value = p.port;
        document.getElementById('secure').value = p.secure;
        document.getElementById('host').style.borderColor = 'rgba(139, 92, 246, 0.4)';
        document.getElementById('port').style.borderColor = 'rgba(139, 92, 246, 0.4)';
        setTimeout(() => {
          document.getElementById('host').style.borderColor = '';
          document.getElementById('port').style.borderColor = '';
        }, 800);
      }
    }

    document.getElementById('secure').addEventListener('change', function() {
      const portMap = { tls: 587, ssl: 465, none: 25 };
      document.getElementById('port').value = portMap[this.value] || 587;
    });

    function togglePassword() {
      const p = document.getElementById('pass');
      const b = document.querySelector('.toggle-pass');
      if (p.type === 'password') { p.type = 'text'; b.textContent = '🙈'; }
      else { p.type = 'password'; b.textContent = '👁'; }
    }

    function getFormData() {
      return {
        host: document.getElementById('host').value.trim(),
        port: document.getElementById('port').value.trim(),
        user: document.getElementById('user').value.trim(),
        pass: document.getElementById('pass').value,
        secure: document.getElementById('secure').value,
        fromEmail: document.getElementById('fromEmail').value.trim(),
        toEmail: document.getElementById('toEmail').value.trim(),
        subject: document.getElementById('subject').value.trim()
      };
    }

    function showToast(success, message) {
      const t = document.getElementById('toast');
      t.className = `toast visible ${success ? 'success' : 'error'}`;
      document.getElementById('toastIcon').textContent = success ? '✅' : '❌';
      document.getElementById('toastText').textContent = message;
      setTimeout(() => { t.className = 'toast'; }, 4000);
    }

    function setLoading(btn, loading) {
      btn.classList.toggle('loading', loading);
      btn.disabled = loading;
    }

    function escapeHtml(text) {
      const d = document.createElement('div'); d.textContent = text; return d.innerHTML;
    }

    function renderResults(data) {
      const header = document.getElementById('resultHeader');
      header.className = `result-header ${data.success ? 'success' : 'error'}`;
      document.getElementById('resultIcon').textContent = data.success ? '✅' : '❌';
      document.getElementById('resultTitle').textContent = data.success ? 'Email Sent Successfully!' : 'Email Sending Failed';

      const stepsEl = document.getElementById('resultSteps');
      stepsEl.innerHTML = '';
      if (data.steps) {
        data.steps.forEach((s, i) => {
          const el = document.createElement('div');
          el.className = 'step';
          el.style.animationDelay = `${i * 0.1}s`;
          const iconMap = { ok: '✓', error: '✗', info: 'ℹ', diagnosis: '?' };
          const sc = s.status || 'info';
          el.innerHTML = `
            <div class="step-icon ${sc}">${iconMap[sc] || '•'}</div>
            <div class="step-text ${sc === 'error' ? 'error' : ''}">${escapeHtml(s.step)}</div>
          `;
          stepsEl.appendChild(el);
        });
      }
      results.className = 'results visible';
      results.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const data = getFormData();
      if (!data.host || !data.port || !data.user || !data.pass || !data.toEmail) {
        showToast(false, 'Please fill in all required fields'); return;
      }
      data.action = 'send';
      setLoading(sendBtn, true);
      results.className = 'results';
      try {
        const res = await fetch(window.location.href, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(data)
        });
        const result = await res.json();
        renderResults(result);
        if (result.success) showToast(true, 'Test email sent! Check your inbox (and spam folder).');
      } catch (err) {
        renderResults({
          success: false,
          steps: [{ step: `Network error: ${err.message}`, status: 'error' }]
        });
      } finally { setLoading(sendBtn, false); }
    });

    async function verifyOnly() {
      const data = getFormData();
      if (!data.host || !data.port || !data.user || !data.pass) {
        showToast(false, 'Please fill in host, port, username, and password'); return;
      }
      data.action = 'verify';
      setLoading(verifyBtn, true);
      try {
        const res = await fetch(window.location.href, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(data)
        });
        const result = await res.json();
        if (result.success) {
          showToast(true, 'Connection verified! Your SMTP credentials are correct.');
        } else {
          showToast(false, 'Verification failed');
        }
        renderResults(result);
      } catch (err) {
        showToast(false, 'Network error: ' + err.message);
      } finally { setLoading(verifyBtn, false); }
    }
  </script>
</body>
</html>
