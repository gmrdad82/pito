# Phase 5 — Slack Probe

> **Goal:** Validate whether Slack is worth being a first-class Pito client
> alongside web, MCP, and the terminal app. This is **explicitly a probe** in
> the Beta-spirit-of-Alpha sense — structured to accept "no" cleanly. The phase
> produces a concrete go/no-go verdict by end of week. If verdict is no,
> populate `dropped.md` with rationale and remove Slack from future phases. If
> yes, Slack joins the regular client maintenance cycle.

**Repo:** Slack app code lives **inside `pito`** (Rails controllers + Sidekiq
jobs). No separate sibling repo.

**Depends on:** Phase 3 (`ApiToken` model + `yt:*` scopes), Phase 4 (design
language locked, JSON API surface mature, cross-client shortcut taxonomy
established).

**Unblocks:** Conditional. If probe succeeds, Slack maintenance lives alongside
other clients from Phase 12 onward. If probe drops, the phases that follow have
one less client to think about.

---

## Why Phase 5 is now

Slack is intentionally placed after the terminal app for three reasons:

1. **API maturity.** The terminal app forced the Web Puma JSON API to be
   complete and clean. Slack uses the same surface — proves whether the API is
   good enough for non-Rails clients in two distinct contexts. If both clients
   work with no special-casing, the API surface is genuinely client-agnostic.
2. **Daily-use validation window.** The user uses Slack daily. A one-week probe
   slot here means the workflow benefit (or lack thereof) is felt during the
   natural rhythm of Beta development, not retroactively. Whatever conclusion
   the probe reaches, it's reached fast.
3. **Cost calibration.** Slack costs include the workspace itself (free tier may
   suffice; paid otherwise), Anthropic API costs for DM-driven Claude
   conversations during the probe (~$5-20 typical), and ongoing maintenance
   attention if it becomes first-class. The probe answers "is the friction worth
   it" before committing to any of those costs long-term.

This phase **must produce a clear go/no-go verdict.** Default outcome is to drop
Slack — the probe must justify keeping it. That bias is intentional: Slack adds
maintenance surface, and Beta should only carry it if it earns its keep.

---

## In scope

### Slack app creation

- Create a Slack app in the user's Slack workspace
- Define manifest in `pito/config/slack/manifest.yml`:
  - Bot scopes: `chat:write`, `commands`, `im:history`, `im:read`, `im:write`,
    `users:read`
  - Slash commands: `/pito`
  - Event subscriptions: `message.im` (DMs to the bot)
- Request URLs (Web Puma):
  - `https://app.pitomd.com/slack/events`
  - `https://app.pitomd.com/slack/commands`
  - `https://app.pitomd.com/slack/oauth`
- Install to workspace; capture bot token, signing secret, app ID

### OAuth + storage

- Migration: `slack_installations` table — `id`, `team_id` (unique),
  `tenant_id`, `bot_token` (encrypted), `bot_user_id`, `installed_by_user_id`,
  `signing_secret` (encrypted), `created_at`
- OAuth callback at `/slack/oauth` — handles `oauth.v2.access` exchange, stores
  installation
- Single-tenant: auto-link the installation to the seeded tenant (Phase 3's
  seeded record)
- Single-active-installation invariant for single-tenant Beta — only one Slack
  workspace per Pito instance

### Probe surface (deliberately small)

The probe deliberately starts small. Every command must justify its existence at
the verdict gate; if it isn't earning its keep, drop it.

- **`/pito stats`** — returns dashboard summary as an ephemeral Slack message
  (today's views, top video, channel count)
- **`/pito channels`** — lists channels with bracketed `[view]` buttons that
  link to `app.pitomd.com/channels/:id`
- **`/pito search <query>`** — runs Web Puma's search endpoint, returns top 5
  with bracketed links
- **`/pito help`** — lists available commands
- **DM the bot in natural language** — bot relays to a Claude conversation that
  has Pito's MCP available; bot responds in the DM thread with the result. This
  is the **most interesting test of the probe**: can Slack be a fourth Claude
  client?

### MCP-routed conversations

When the user DMs the bot, the bot relays the message to a Claude conversation:

- The bot has a dedicated `slack-bot` `ApiToken` with scopes `yt:read yt:write`
  (no destructive — destructive operations require a token elevated through a
  different path, not the Slack bot)
- The bot calls the Anthropic API with `mcp.pitomd.com` registered as an MCP
  server, the `slack-bot` token as the bearer, and the user's Slack message as
  the prompt
- Response from Claude posts back to the DM thread
- Background processing via Sidekiq (`SlackInboundJob`); bot responds with eyes
  emoji immediately to indicate work is in flight

The Anthropic API key is stored in Rails credentials. A daily token-budget cap
is enforced (configurable via `SLACK_PROBE_DAILY_TOKEN_LIMIT`) to prevent
runaway costs during testing.

### Auth coupling

- The Slack workspace is tied to the seeded tenant (single-tenant Beta)
- The `slack-bot` `ApiToken` lives in Pito's `api_tokens` table (Phase 3 model),
  owned by the seeded user, with scopes `yt:read yt:write`
- All Slack-driven actions through MCP are scope-checked exactly like any other
  MCP request (Phase 3's auth concern doesn't care that the token is being used
  by Slack)

### Signature verification

Every incoming Slack request must be signature-verified:

- Validate `X-Slack-Signature` header using HMAC-SHA256 with the signing secret
- Reject requests with timestamps older than 5 minutes (Slack replay protection)
- Constant-time comparison
- Verification happens **before** parsing the body (raw body access required)

### Out of scope

- Microsoft Teams (deferred indefinitely; if Slack probe succeeds, Teams
  revisited at Phase 16 or post-Beta)
- Slack workflows / app home / shortcuts beyond the probe surface
- Multi-workspace support (single workspace, single tenant)
- Slack-specific UI design tokens (use Slack defaults; if probe succeeds,
  `pito/docs/design.md` gets a Slack section)
- Channel-targeted notifications ("auto-post when a video uploads") — Phase 13
  concern if Slack survives
- Slack file uploads / image attachments
- Threading beyond the bot's own DM responses

---

## Validation criteria — the verdict gate

After implementation completes, the user spends **one work-week** using Slack as
a Pito client. At the end of that week, evaluate against four axes:

1. **Utility.** Did Slack offer something genuinely useful that web/MCP/terminal
   didn't? Or did it duplicate existing surfaces with no marginal benefit?
2. **Friction.** Was the user actively using `/pito` commands or DMs, or
   forgetting they exist? Discovery is part of utility — if the surface was
   always-out-of-mind, that's a vote for drop.
3. **Reliability.** Were there Slack-specific edge cases (rate limits, signature
   failures, payload limits, formatting quirks) that ate engineering time
   disproportionate to the value delivered?
4. **Cost.** Is the Slack tier sufficient, or does sustained use require a paid
   plan? What did the Anthropic API cost during the week?

**Verdict outcomes:**

- **YES (continue, become first-class):** Slack joins the regular client roster.
  Phase 12+ maintains it alongside other clients. Document the probe outcome in
  `log.md`.
- **NO (drop, document):** Populate `dropped.md` with rationale. Remove Slack
  from future phase plans where it appears (Phase 12 auth UI, Phase 13
  observability sections, Phase 16 deployment). Keep the code in a branch for
  posterity but don't merge to `main`.

The default outcome bias is **drop**. The probe must produce affirmative
evidence to justify keeping Slack.

---

## Plan checklist

### Slack app creation

- [ ] Create Slack app in the user's workspace via the Slack admin UI or via
      manifest API
- [ ] Define manifest in `pito/config/slack/manifest.yml` with the scopes and
      event subscriptions listed above
- [ ] Set request URLs to point at Web Puma endpoints
- [ ] Install to workspace; capture bot token, signing secret, app ID
- [ ] Store credentials in Rails credentials

### OAuth + persistence

- [ ] Migration: `slack_installations` table with encrypted token fields
- [ ] `SlackInstallation` model with associations and validations
- [ ] OAuth callback controller at `/slack/oauth` — handles `oauth.v2.access`
      exchange
- [ ] Specs for the OAuth flow, encryption, and single-tenant linking

### Slash commands

- [ ] `POST /slack/commands` controller — verify signature first, then dispatch
      by command text
- [ ] `/pito stats` handler — calls Web Puma's dashboard JSON endpoint, formats
      response as Slack message
- [ ] `/pito channels` handler — calls channels JSON endpoint, formats with
      bracketed links
- [ ] `/pito search <query>` handler — calls search JSON endpoint, returns top 5
- [ ] `/pito help` handler — static response listing commands
- [ ] All handlers return within 3 seconds (Slack timeout); longer work goes via
      `response_url` follow-up

### DM-driven Claude conversations

- [ ] `POST /slack/events` controller — verify signature, handle
      `event_callback` of type `message.im`
- [ ] DMs enqueue a `SlackInboundJob` (Sidekiq); bot responds with eyes emoji
      immediately
- [ ] `SlackInboundJob` calls Anthropic API with `mcp.pitomd.com` as an MCP
      server, using the `slack-bot` token
- [ ] Response posts back to the DM thread via `chat.postMessage`
- [ ] Daily token-budget cap enforced; on exceed, bot responds with a clear
      "daily budget exhausted, try tomorrow" message
- [ ] Specs for: signature pass/fail, message routing, job enqueue, mocked
      Anthropic call, token budget enforcement

### Signature verification

- [ ] Implement `Slack::SignatureVerifier` — constant-time HMAC-SHA256, 5-minute
      timestamp window
- [ ] Apply to `/slack/commands` and `/slack/events` controllers
- [ ] Specs: valid signature, invalid signature, expired timestamp, replay
      attempt

### Auth + token

- [ ] Create the `slack-bot` `ApiToken` via the Settings UI established in Phase
      3 (or a one-off seed for the probe period); scopes `yt:read yt:write`
- [ ] `SlackInboundJob` reads the token from a config entry
      (`SLACK_BOT_API_TOKEN_ID` or stored in credentials)
- [ ] Standard scope enforcement applies — Slack tries to call a destructive
      tool, gets rejected by Phase 3's auth concern, surfaces the error in the
      DM response

### Rate limiting

- [ ] Rack::Attack rule on `/slack/events` and `/slack/commands` — 30 req/min
      per IP (Slack itself rate-limits, but defense-in-depth)

### Documentation

- [ ] `pito/docs/architecture.md`: conditional Slack client section (added if
      probe succeeds; describes the architecture clearly)
- [ ] `pito/docs/slack.md` — only created if probe succeeds. Manifest, install
      flow, command surface, troubleshooting.
- [ ] `pito/docs/design.md`: Slack message styling notes if probe succeeds

### Validation

- [ ] Manual: install Slack app to workspace; OAuth completes
- [ ] Manual: `/pito stats`, `/pito channels`, `/pito search`, `/pito help` all
      return expected output
- [ ] Manual: DM the bot a natural-language question; receives a
      Claude-generated response within 30 seconds
- [ ] Manual: signature verification rejects forged requests
- [ ] Manual: daily token budget enforced; bot responds gracefully when
      exhausted
- [ ] One full work-week of real-world usage
- [ ] **Verdict captured in `log.md`**
- [ ] If verdict is NO: `dropped.md` populated with rationale; future phases
      updated to remove Slack references
- [ ] All RSpec specs pass
- [ ] Brakeman clean
- [ ] bundler-audit clean
- [ ] Dependabot reviewed

---

## Specs requirements

- Signature verification: valid, invalid, expired (>5 min old), replay attempt,
  missing header.
- Slash command dispatch: each command routes to its handler, returns expected
  payload shape.
- DM event handler: message creates a Sidekiq job; job calls mocked Anthropic
  API and responds via `chat.postMessage`.
- OAuth installation: store, retrieve, single-tenant invariant.
- Rate limiting: throttle triggers correctly under burst load.
- Token budget enforcement: under-budget proceeds, over-budget rejects with
  clear message.

## Security requirements

- Slack signing secret in Rails credentials, encrypted attribute on
  `SlackInstallation`.
- Bot token encrypted at rest.
- Signature verification uses constant-time HMAC comparison and rejects
  timestamps >5 minutes old.
- Anthropic API key in Rails credentials.
- The `slack-bot` `ApiToken` does **not** have `yt:destructive` scope.
  Destructive operations through Slack require a separate, explicit token
  elevation that goes through the web Settings UI — Slack DM cannot escalate
  scopes itself.
- Brakeman: no new warnings.
- bundler-audit: clean.
- Dependabot: review after additions.
- `pito/docs/design.md`: minor update if probe succeeds.

## Manual testing checklist

The user runs through this during the probe week:

1. Install Slack app to workspace; OAuth completes; row appears in
   `slack_installations`
2. In any channel: `/pito stats` — ephemeral message with dashboard summary
3. `/pito channels` — list with bracketed `[view]` links that open the web app
4. `/pito search ratchet` — top 5 search results
5. DM the bot: "what are my top 3 videos this month?" — bot responds via
   Claude+MCP within 30s
6. DM the bot: "create a channel called Test" — bot uses MCP `create_channel`
   (or Beta-equivalent) tool and confirms
7. DM the bot: "delete the Test channel" — bot attempts via MCP, gets scope
   rejection from Phase 3's auth concern, responds with the rejection message
8. Forge a request to `/slack/commands` with a bad signature — 401
9. Send a request with a timestamp 10 minutes old — 401
10. Hit the token budget cap (artificially low for testing); verify graceful
    "budget exhausted" response
11. **Daily during the probe week**: note instances where Slack was useful AND
    instances where it was forgotten/redundant
12. **End of week**: write the verdict in `log.md`

---

## Challenges to anticipate

- **Slack signature verification timing.** Verify before parsing body. Raw body
  access in Rails requires bypassing the default JSON parser for the relevant
  routes — typically via a `before_action` that reads `request.raw_post`
  directly.
- **3-second slash command timeout.** Slack expects an HTTP response within 3s.
  For longer operations (DM-Claude conversations), respond immediately with a
  quick acknowledgment and follow up via `response_url` once work completes.
- **MCP HTTP transport from Sidekiq.** Confirm the `SlackInboundJob` running in
  Sidekiq can reach `mcp.pitomd.com` via DNS. If networking issues arise,
  fallback to direct internal HTTP at `http://localhost:<mcp-port>/mcp`.
- **Anthropic API costs.** Every Claude DM is a paid API call. The daily budget
  cap exists to prevent runaway costs during the probe. Set a sensible default
  ($1/day during probe; raise if probe succeeds).
- **Probe scope creep.** If the probe is going well midweek, resist adding "just
  one more" feature. The verdict is the deliverable, not features. Note ideas in
  `additions.md` for post-verdict consideration.
- **The probe might end with a "kind of useful" verdict.** If neither a clean
  YES nor a clean NO, default to NO. Slack maintenance is real ongoing cost; the
  bar to keep it should be "clearly net positive," not "neither obviously good
  nor obviously bad."

---

## `dropped.md` template (use if verdict is NO)

If the verdict is NO, create `docs/plans/beta/05-slack-probe/dropped.md` with
this structure:

```markdown
# Phase 5 — Dropped

**Verdict:** NO. Slack is not a first-class Pito client.
**Date:** YYYY-MM-DD
**Probe duration:** N days

## What was built

(Brief summary of what shipped during the probe — slash commands, DM-Claude routing, signature verification, etc.)

## Why dropped

### Utility
(What did Slack offer? Was it duplicative of web/MCP/terminal?)

### Friction
(How often did the user actually use it? Did discovery work?)

### Reliability
(What broke? What was Slack-specific overhead?)

### Cost
(What did the probe cost in Anthropic tokens, time, attention?)

## Code disposition

- Branch: `slack-probe-archive` (preserved on GitHub, not merged to main)
- Migrations rolled back in dev
- `slack_installations` table dropped in dev
- Anthropic API key removed from Rails credentials
- `pito/config/slack/manifest.yml` deleted
- `pito/docs/architecture.md` updated to remove Slack references

## Future phase impact

- Phase 12 (Auth UI): Slack OAuth flow not needed; remove from auth UI scope
- Phase 13 (Observability): Slack-related metrics not tracked
- Phase 16 (Hetzner Deployment): Slack endpoints not deployed

## Lessons learned

(What did the probe teach us about Pito's API, about the JSON surface, about the value of conversational interfaces, about Slack as a platform?)
```

This template is referenced from this `plan.md` so Claude Code knows exactly
what to populate if the verdict is NO. The template is **not pre-created** —
only created if needed, populated at verdict time.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user has a Slack workspace they can install apps to.
2. The user is OK with Anthropic API costs during the probe (typical: $5-20 for
   a week of testing).
3. The user understands the verdict is binary (YES or NO) and recorded in
   `log.md`. NO populates `dropped.md`.
4. The user is OK with single-workspace, single-tenant assumption for the probe.
5. The default-bias is to drop. Confirm the user understands and agrees with
   this bias.
6. Daily token budget cap default ($1/day) is acceptable during the probe.
