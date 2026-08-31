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
4. You should end up with 10 tables: `accounts`, `profiles`, `favorites`,
   `history`, `devices`, `device_tokens`, `admins`, `sync_log`,
   `pairing_codes`, `rate_limits`.

**Already deployed from before the anonymous-accounts change?** Don't
re-import `schema.sql` over live data — instead run
`backend/sql/migrate_v2_anonymous_accounts.sql` once (same Import tab). It's
idempotent (safe to run more than once) and only widens two columns to
nullable plus adds the new `pairing_codes` table; it doesn't touch existing
rows.

## 3. Upload the backend files

Upload the entire contents of this `backend/` folder (keeping the folder
structure intact) via cPanel **File Manager** or FTP/SFTP. Two reasonable
places to put it:

- **A subdomain** (cleaner): create `api.yourdomain.com` in cPanel → **Domains**,
  pointed at a new folder (e.g. `api`), then upload the contents of `backend/`
  directly into that folder's root. The login endpoint then ends up at
  `https://api.yourdomain.com/api/account/register.php`.
- **A subfolder of your main site** (simpler, no subdomain needed): upload the
  contents of `backend/` into `public_html/backend/`. The endpoint is then at
  `https://yourdomain.com/backend/api/account/register.php`.

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

`login.php` no longer exists — it took an Xtream server/username/password and
authenticated against a user's own streaming service, which is exactly what
Apple's Guideline 5.6 rejection flagged (see the account_id.php doc comment
in `lib/account_id.php` for the full reasoning). It's been replaced by
`register.php`, which never sees any Xtream credential at all — it just
hands out an opaque, random account and a device token.

Replace `YOUR_DEPLOYED_URL` and `YOUR_API_KEY` below, then run:

```bash
curl -i -X POST "https://YOUR_DEPLOYED_URL/api/account/register.php" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: YOUR_API_KEY" \
  -d '{
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
`profiles` is an empty array for a brand-new account — expected, not a bug.

**Expected failure responses** you might hit while testing:
- Wrong/missing `X-Api-Key` → HTTP 401, `error.code: "INVALID_API_KEY"`.
- Missing `device_id`/`device_name`/`platform` → HTTP 400, `error.code:
  "INVALID_BODY"`.
- More than 10 attempts within an hour from the same device_id, or 60/hour
  from the same IP → HTTP 429, `error.code: "RATE_LIMITED"`.

Please run this and paste back exactly what you get (including the HTTP
status line from `-i`) — especially if it's anything other than the success
shape above, since that's the fastest way for me to tell what's wrong.

### The other account endpoints

All three require the `device_token` from `register.php` as
`Authorization: Bearer <device_token>`, plus the same `X-Api-Key` header.

- **`POST /api/account/pairing_code.php`** — no body. Returns
  `{"code": "AB23CD45", "expires_at": "..."}`, an 8-character code valid for
  15 minutes, multi-use within that window. Shown in Settings → "Show my
  sync code" in the app.
  ```bash
  curl -i -X POST "https://YOUR_DEPLOYED_URL/api/account/pairing_code.php" \
    -H "X-Api-Key: YOUR_API_KEY" \
    -H "Authorization: Bearer YOUR_DEVICE_TOKEN"
  ```
- **`POST /api/account/join.php`** — `{"code": "AB23CD45"}`. Moves *this*
  device onto the account the code was issued for and mints it a fresh
  token; the response shape matches `register.php`'s. An expired/wrong code
  is `error.code: "INVALID_CODE"` (404).
- **`POST /api/account/migrate_legacy.php`** — `{"server_url": "...",
  "username": "..."}`. One-time bridge for accounts created before this
  change: recomputes the old SHA256(server_url+username) account_id
  server-side and, if it finds a match, folds its profiles/devices/tokens
  into the caller's new anonymous account. Returns `{"migrated": false}` for
  anyone who never had a legacy account — that's the expected response for
  every brand-new install, not an error. The app calls this automatically
  once per fresh registration when it still has a saved server_url/username
  locally, so you shouldn't normally need to call it by hand.

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

## `demo-iptv/` — the App Store / Play Store review account

This is a separate, self-contained thing from the rest of `backend/` — it
doesn't touch the database, `config.php`, or the account/profile/sync API
above at all. It's a tiny real Xtream Codes–compatible server
(`demo-iptv/player_api.php`), used only to give App Store/Play Store
reviewers a real account to log into.

**Why it exists**: the app used to detect a magic `server=demo` login and
swap in fake, fully local data on the client instead of ever calling a real
server — reviewers saw a different app than real users. Apple rejected that
under Guideline 5.6 (Developer Code of Conduct) for exactly what it was.
That client-side branch has been deleted. This folder replaces it with a
*real* server speaking the *real* Xtream protocol — the app has zero
special-casing left for it. The only thing "demo" about the account is that
its content is a handful of openly-licensed public test videos (Blender
Foundation's Big Buck Bunny/Sintel, Apple's own published HLS test stream,
Mux's public test stream — see the doc comment in `demo-iptv/demo_content.php`
for exact sources/licenses), not a real IPTV lineup.

**Deploy**: upload the `demo-iptv/` folder the same way as the rest of
`backend/` (step 3 above) — e.g. into `api.shitaa.online/demo-iptv/` if
you're using the same subdomain as the main backend. No `config.php`
editing needed; it has no dependencies on the rest of this folder.

**Give these to App Review** (Sign-In Information / Notes in App Store
Connect, and the equivalent in Play Console's "Sign in details"):
- Server URL: `https://api.shitaa.online/demo-iptv` (adjust the host to
  wherever you actually uploaded it)
- Username: `demo`
- Password: `demo`

**Test it yourself first** — log into the app with those exact credentials
before you resubmit, and confirm you personally see: live playback, movie
playback with a working download button on "Big Buck Bunny" specifically
(it's the one non-HLS file), a series with two episodes, and the normal
profile picker on first login. If any of that doesn't work for you, it won't
work for the reviewer either.

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
