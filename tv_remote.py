#!/usr/bin/env python3
"""Lightweight browser-based remote control for the Android TV emulator.

For when the emulator window itself won't take keyboard focus (a common
macOS quirk when the emulator was launched from a background/terminal
process) but mouse clicks on it work fine: this serves a tiny local page
with D-pad buttons, and every click runs the matching
`adb shell input keyevent ...` for you — no keyboard input to the emulator
window required at all.

Usage:
    python3 tv_remote.py
    # then open http://localhost:8765 in a browser and click around

Stdlib only — no pip installs needed. Requires `adb` on PATH (already true
if you've built/run this project) and a connected device/emulator.
"""

import http.server
import socketserver
import subprocess
import urllib.parse

PORT = 8765

KEY_MAP = {
    "up": "KEYCODE_DPAD_UP",
    "down": "KEYCODE_DPAD_DOWN",
    "left": "KEYCODE_DPAD_LEFT",
    "right": "KEYCODE_DPAD_RIGHT",
    "ok": "KEYCODE_DPAD_CENTER",
    "back": "KEYCODE_BACK",
    "home": "KEYCODE_HOME",
    "play_pause": "KEYCODE_MEDIA_PLAY_PAUSE",
}

PAGE = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>TV Remote</title>
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; height: 100vh; display: flex; flex-direction: column;
    align-items: center; justify-content: center; gap: 24px;
    background: #0b0b0f; font-family: -apple-system, sans-serif;
  }
  #status { color: #8b5cf6; font-size: 13px; min-height: 16px; }
  .dpad {
    display: grid;
    grid-template-columns: 64px 64px 64px;
    grid-template-rows: 64px 64px 64px;
    gap: 6px;
  }
  button {
    border: 1px solid #27272a; background: #18181f; color: #fff;
    border-radius: 10px; font-size: 22px; cursor: pointer;
  }
  button:active { background: #7c3aed; }
  .up { grid-column: 2; grid-row: 1; }
  .left { grid-column: 1; grid-row: 2; }
  .ok { grid-column: 2; grid-row: 2; background: #7c3aed; }
  .right { grid-column: 3; grid-row: 2; }
  .down { grid-column: 2; grid-row: 3; }
  .row { display: flex; gap: 10px; }
  .row button {
    width: 90px; height: 44px; font-size: 14px; border-radius: 22px;
  }
</style>
</head>
<body>
  <div class="dpad">
    <button class="up" onclick="press('up')">&#9650;</button>
    <button class="left" onclick="press('left')">&#9664;</button>
    <button class="ok" onclick="press('ok')">OK</button>
    <button class="right" onclick="press('right')">&#9654;</button>
    <button class="down" onclick="press('down')">&#9660;</button>
  </div>
  <div class="row">
    <button onclick="press('back')">Back</button>
    <button onclick="press('home')">Home</button>
    <button onclick="press('play_pause')">Play/Pause</button>
  </div>
  <div id="status"></div>
<script>
async function press(key) {
  const status = document.getElementById('status');
  try {
    const res = await fetch('/key/' + key);
    status.textContent = res.ok ? key + ' sent' : 'no device found';
  } catch (e) {
    status.textContent = 'server not reachable';
  }
  setTimeout(() => { status.textContent = ''; }, 700);
}
document.addEventListener('keydown', (e) => {
  const map = {
    ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
    Enter: 'ok', ' ': 'ok', Backspace: 'back', Escape: 'back',
  };
  if (map[e.key]) press(map[e.key]);
});
</script>
</body>
</html>
"""


def _target_device():
    try:
        out = subprocess.run(
            ["adb", "devices"], capture_output=True, text=True, timeout=5
        ).stdout
    except Exception:
        return None
    for line in out.splitlines()[1:]:
        line = line.strip()
        if line.endswith("\tdevice"):
            return line.split("\t")[0]
    return None


class Handler(http.server.BaseHTTPRequestHandler):
    def _run_adb(self, code):
        device = _target_device()
        if not device:
            return False
        cmd = ["adb", "-s", device, "shell", "input", "keyevent", code]
        subprocess.run(cmd, capture_output=True, timeout=5)
        return True

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/":
            body = PAGE.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif parsed.path.startswith("/key/"):
            key = parsed.path.split("/key/", 1)[1]
            code = KEY_MAP.get(key)
            ok = code is not None and self._run_adb(code)
            self.send_response(204 if ok else 404)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # keep the terminal quiet


if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        print(f"TV remote running — open http://localhost:{PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
