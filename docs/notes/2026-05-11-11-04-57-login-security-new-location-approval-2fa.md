# Login security + new-location approval flow

Context: I'm going to start making videos about pito — how I use it, how I built
it, what it does. The address bar will be visible on camera. Logically nothing
happens without login, but I want extra defense in depth and extra awareness
around access attempts.

## Goals

- Log every login attempt and fingerprint it.
- Detect "new location" attempts and require explicit approval.
- Surface pending approvals across web, TUI, and MCP — approve or block from any
  of them.
- Integrate 1Password 2FA as the primary challenge for new-location logins.
- Hold to current security standards, and lean strict — I care about my privacy
  and my work.

## Login attempt logging + fingerprinting

Every login attempt (success or failure) gets a row. Fields:

- timestamp
- result (success / failed / pending_approval / blocked)
- IP address
- approximate geolocation (city / region / country) derived from IP
- user-agent string parsed into browser + OS
- a stable-ish browser/device fingerprint (consider FingerprintJS-style hash or
  our own composite: UA + accept headers + screen/locale hints we can grab
  safely)
- reason (e.g. wrong_password, new_location, 2fa_passed, approved_from_tui)
- linked Notification id when applicable

Stored in DB. Never auto-purged. Manual purge available (see "purge" below).

## New-location detection

"New location" = the (fingerprint, IP-prefix-or-geo) combination has never been
seen on a successful login before. Behave Google-style: if the system sees a new
location / device, challenge.

On a new-location login attempt with correct password, the login screen offers
two paths:

1. **[Enter 1Password 2FA]** — primary path. If 2FA clears, the login succeeds,
   the location/fingerprint is recorded as trusted, and **no pending-approval
   notification is created.**
2. **[Ask for approval]** — fallback path when I don't have 1Password handy.
   Creates a pending-approval Notification, holds the session in
   `pending_approval`, waits for approve/block from another surface.

If 2FA fails, treat as failed attempt and log it.

## Notifications surface

When the user chooses `[ask for approval]`:

- Create a Notification (uses the existing notifications system — Phase 16).
- Notification renders on:
  - Web app
  - TUI
  - MCP (new tool, see below)
- Notification shows: time, IP, geo, browser/OS, fingerprint summary.
- Actions: `[yeah, it's me]` (approve) / `[block the intruder]` (block).
- Approving releases the pending session and marks the fingerprint trusted.
- Blocking marks the attempt as blocked, invalidates the pending session, and
  tags the IP/fingerprint for future auto-block (configurable).
- Once approved or blocked, the notification resolves itself (no lingering
  banner).

## MCP tool

New MCP tool (working name `login_attempts_pending`) returns currently-pending
approval requests with full detail. Companion tool (or single tool with action
arg) lets me say:

- `approve` — same as `[yeah, it's me]`
- `block` — same as `[block the intruder]`

Plus a `login_attempts_list` tool to browse historical attempts (filterable by
result, since, IP, fingerprint) for cross-referencing.

## Purge

I need to undo a wrong block. Required:

- View blocked attempts.
- Unblock individual attempts (clears the auto-block tag on that
  fingerprint/IP).
- Bulk purge by filter if I get spammed.

Available on web + MCP. Maybe TUI later.

## 1Password 2FA integration

- Use TOTP standard — 1Password just stores the seed. Anything TOTP-compatible
  works.
- Seed provisioned during setup, QR code shown once.
- Backup codes generated and shown once (printable).
- Enforce on every new-location login. Existing trusted devices don't get
  re-challenged unless something else looks off (IP jump mid-session,
  fingerprint change, etc. — TBD threshold).

## Security standards to apply

- Rate-limit login attempts per IP and per account (exponential backoff).
- Constant-time password comparison (already standard via bcrypt/Devise).
- Session fixation protection on login.
- Rotate session token on successful 2FA.
- Hash fingerprints at rest, not plaintext.
- IP-prefix matching (not exact IP) for "same location" since residential IPs
  rotate — /24 for IPv4, /64 for IPv6 as a starting point.
- All approval/block actions audit-logged separately from the attempt log.
- Pending-approval sessions expire (e.g. 10 min) if no approve/block decision
  arrives.
- Don't leak which step failed (wrong password vs unknown account) on the login
  form.

## Dispatch

Dispatch agents to spec and build this asap. Suggested phase split:

1. **Attempt logging + fingerprint model + IP/geo enrichment** (foundation,
   ships independently).
2. **New-location detection + pending-session state machine.**
3. **Notifications integration (web + TUI) with approve/block actions.**
4. **MCP tools (`login_attempts_pending`, `login_attempts_list`, approve/block,
   purge).**
5. **1Password / TOTP 2FA integration + backup codes.**
6. **Auto-block list + purge UI.**
7. **Rate limiting + session hardening pass.**
8. **End-to-end system specs covering: new location → 2FA path, new location →
   ask-for-approval path → approve from MCP, → block from TUI, → wrong-block
   purge.**

Exhaustive specs at every layer. This is on-camera infrastructure — it has to be
right.
