# GenZ+ Backend

Plain PHP 8+ / MySQL REST API, no framework, built for stock shared cPanel
hosting — plus a server-rendered admin panel under `admin/`. Covers accounts/
device-token auth, Netflix-style profiles, favorites/history cloud sync with
an offline-first queue on the Flutter side, device management, and admin
tooling (dashboard, account/profile search, suspend/delete, force-logout).

I could not run or deploy any of this myself — there's no PHP or MySQL
available in the environment I built it in (confirmed via `which php mysql
mariadb`, all empty). Everything has been carefully reviewed by hand
(including two real bugs I found and fixed on review — see the `PDO::
ATTR_EMULATE_PREPARES` note in `lib/db.php`'s doc comment: with native
prepares, the same named placeholder can't appear twice in one query, which
bit two dynamically-built queries in `admin/`), and the API portion has been
smoke-tested against a real deployment (see `curl` steps below). Please run
through anything new you haven't tried yet and share what you get.

## 1. Create the database (cPanel)

1. cPanel → **MySQL® Database Wizard**.
2. Create a new database (cPanel will prefix it with your account name, e.g.
   `cpaneluser_genz`).
3. Create a new database user with a strong password, and add it to the
   database with **All Privileges**.
4. Note the three values cPanel shows you: the full database name, the full
   username, and the password — you'll need them in step 3 below.

## 2. Import the schema

1. cPanel → **phpMyAdmin**.
2. Select the database you just created.
3. **Import** tab → choose file → `backend/sql/schema.sql` → Go.
4. You should end up with 9 tables: `accounts`, `profiles`, `favorites`,
   `history`, `devices`, `device_tokens`, `admins`, `sync_log`, `rate_limits`.
   (Only `accounts`, `devices`, `device_tokens`, and `rate_limits` are
   actually used by anything in Phase 0 — the rest exist now because they're
   part of the foundational schema, but stay empty until later phases.)

## 3. Upload the backend files

Upload the entire contents of this `backend/` folder (keeping the folder
structure intact) via cPanel **File Manager** or FTP/SFTP. Two reasonable
places to put it:

- **A subdomain** (cleaner): create `api.yourdomain.com` in cPanel → **Domains**,
  pointed at a new folder (e.g. `api`), then upload the contents of `backend/`
  directly into that folder's root. The login endpoint then ends up at
  `https://api.yourdomain.com/api/account/login.php`.
- **A subfolder of your main site** (simpler, no subdomain needed): upload the
  contents of `backend/` into `public_html/backend/`. The endpoint is then at
  `https://yourdomain.com/backend/api/account/login.php`.

Either way, the relative structure inside must stay exactly as it is in this
repo (`api/`, `lib/`, `sql/`, `config.php`, `.htaccess` files all siblings).

## 4. Configure `config.php`

Edit the uploaded `config.php` (via File Manager's built-in editor, or edit
locally and re-upload) and fill in:

- `DB_HOST` — almost always `localhost` on cPanel.
- `DB_NAME` / `DB_USER` / `DB_PASS` — the values from step 1.
- `API_KEY` — any long random string. If you have terminal/SSH access on
  your host, generate one with either:
  ```
  php -r "echo bin2hex(random_bytes(32));"
  ```
  or
  ```
  openssl rand -hex 32
  ```
  If you don't have terminal access, any long, hard-to-guess random string
  works just as well — it doesn't need to come from that exact command.
- Leave `DEBUG_MODE` as `false` for anything other than initial testing.

**Keep this file private** — it's already blocked from direct web access by
`backend/.htaccess`, but don't paste its contents anywhere public either,
since it holds your real database credentials.

## 5. Confirm PHP version + extensions

cPanel → **Select PHP Version** (sometimes called "MultiPHP Manager"):
- Set the domain/subdomain this is deployed under to **PHP 8.1 or newer**.
- Confirm these extensions are enabled (all are on by default in cPanel's PHP
  Selector, but worth a glance): `curl`, `json`, `pdo_mysql`, `mbstring`.

## 6. Test it

Replace the placeholders below with your real values (a real Xtream
server/username/password, the API key you set in step 4, and the URL you
deployed to), then run:

```bash
curl -i -X POST "https://YOUR_DEPLOYED_URL/api/account/login.php" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: YOUR_API_KEY" \
  -d '{
    "server_url": "http://example.com",
    "username": "your_xtream_username",
    "password": "your_xtream_password",
    "device_id": "11111111-1111-1111-1111-111111111111",
    "device_name": "Test Curl",
    "platform": "test"
  }'
```

**Expected success response** (HTTP 200):
```json
{
  "success": true,
  "data": {
    "account_id": "a 64-character hex string",
    "device_token": "a 64-character hex string",
    "expires_at": "2026-11-03 12:00:00",
    "profiles": []
  },
  "error": null
}
```
`profiles` being an empty array is expected in this phase — that's not a bug,
just a stub for the profiles endpoint a later phase adds.

**Expected failure responses** you might hit while testing:
- Wrong/missing `X-Api-Key` → HTTP 401, `error.code: "INVALID_API_KEY"`.
- Wrong Xtream username/password → HTTP 401, `error.code: "XTREAM_AUTH_FAILED"`.
- Unreachable/invalid server_url → HTTP 401, `error.code: "XTREAM_AUTH_FAILED"`,
  with a message explaining why (couldn't reach it, invalid scheme, etc).
- More than 10 attempts within an hour from the same IP → HTTP 429,
  `error.code: "RATE_LIMITED"`.

Please run this and paste back exactly what you get (including the HTTP
status line from `-i`) — especially if it's anything other than the success
shape above, since that's the fastest way for me to tell what's wrong.

## Admin panel

Server-rendered PHP under `admin/` (session-based login, separate from the
app's bearer-token API auth). Deploy it as part of the same `backend/`
upload — no separate steps needed beyond what's above.

**One-time setup**: visit `https://YOUR_DEPLOYED_URL/admin/setup.php` in a
browser. It only works once — the moment any admin account exists, it
permanently refuses to create another (so it can't become a standing
backdoor). Pick a username and a password (10+ characters), then log in at
`admin/login.php`.

What it can do: dashboard with account/profile/favorite/history counts and
"online today" figure; search/paginate all accounts; suspend, unsuspend, or
permanently delete an account (cascades to all its data); per-account view
of its profiles and devices; clear an individual profile's favorites/history
(in bulk or one row at a time); force-logout a device.

Consider deleting `admin/setup.php` after you've created your admin account,
or at least don't leave the URL lying around — it's inert once an admin
exists, but there's no reason to keep it reachable either.

## What's deliberately not included

- No batched `/api/sync/push` / `/api/sync/pull` endpoints — the Flutter
  sync queue replays individual favorites/history calls instead. Simpler
  surface, costs more round trips on a large offline backlog; revisit if
  that ever matters in practice.
- No cron-based cleanup of `sync_log`/`rate_limits` yet — both grow
  unboundedly for now. Fine at small scale; add a pruning job (or an admin
  "Clean Up" button) once it matters.
- SSRF protection on the Xtream re-validation call has one disclosed gap: a
  small window between our DNS check and curl's own resolution (DNS
  rebinding) — see the doc comment on `assert_safe_xtream_url()` in
  `lib/xtream_client.php`.
