# ADR 0017 — Cable-first architecture: contract, channel naming, and payload schema

## Status

Proposed — locked 2026-05-20 as part of Beta 4 foundation. Gates F1
ViewComponent dispatches.

## Context

ADR 0016 declared cable-first hybrid architecture: first-paint server-side
renders the LAYOUT with reserved dimensions + placeholder cells; cable
subscriptions populate the inner content of each cell without resizing.
This ADR specifies the concrete contract.

Key constraints (recap):

- CLS guarantee = 0 (no layout shift on cable arrival)
- Ratatui Rust client + pito web both subscribe to the same channels
- Per-panel subscriptions (one ViewComponent = one channel subscription)
- Server is lightweight: token management, channel auth, payload
  broadcast — no rendering

## Decision

### Channel naming convention

Use a hierarchical naming scheme:

```
pito:<section>:<panel>[:<scope>]
```

Examples:

```
pito:powerline:synced              # global sync indicator
pito:powerline:sidekiq             # global Sidekiq queue stats
pito:channels:<id>:overview        # per-channel overview panel
pito:channels:<id>:top_content     # per-channel top content table
pito:games:<id>:rhm                # per-game rating heat bar (rarely updates)
pito:games:<id>:ttb                # per-game time-to-beat bar
pito:games:<id>:recommendations    # per-game channel recommendations
pito:bundles:<id>:cover            # per-bundle compound cover art status
pito:settings:stack:postgres       # per-subsystem stack stats
pito:settings:stack:sidekiq        # mirror of powerline sidekiq
```

Section + panel are mandatory. Scope (channel id, game id, etc.) is
optional.

### Subscription pattern

- Each ViewComponent that needs live data declares its channel via a
  `data-cable-channel` attribute on its root element
- A single Stimulus controller (`cable-panel`) reads the attribute on
  connect and subscribes to ActionCable
- On payload receipt: controller dispatches a custom event with the
  payload; the ViewComponent's child Stimulus controllers handle
  rendering
- On disconnect: controller unsubscribes cleanly
- Channels are AUTHORIZED in the channel class — non-authorized clients
  get rejected on subscribe (e.g. user must be authenticated; for
  per-channel scope, user must be the owner of that channel)

### Payload schema

All cable payloads share a common envelope:

```json
{
  "kind": "<state>",
  "payload": { ... },
  "ts": "<iso-8601-utc>"
}
```

`kind` enum:

- `idle` — default/quiet state. Payload may be empty or carry latest
  data.
- `indeterminate` — operation in progress, no progress info. Indicator
  slot shows braille spinner.
- `progress` — operation in progress WITH progress info. Payload
  includes `current`, `total`, `label`. Indicator slot shows ASCII bar
  + counter.
- `complete` — operation finished successfully. Payload carries the
  resulting data. Indicator snaps back to idle green.
- `error` — operation failed. Payload includes `message`, `code`
  (optional). Indicator shows red X persistent until reconnect/retry.
- `data` — fresh data push WITHOUT a state change (idle remains idle
  but content updated). For Sidekiq stats, latest queue depths.

Examples:

```json
// Sidekiq stats push
{
  "kind": "data",
  "payload": { "busy": 12, "scheduled": 5, "enqueued": 33, "retry": 0 },
  "ts": "2026-05-20T14:23:00Z"
}

// Compound cover art recompute progress
{
  "kind": "progress",
  "payload": { "current": 12, "total": 33, "label": "syncing channels" },
  "ts": "2026-05-20T14:23:05Z"
}

// Channel sync complete
{
  "kind": "complete",
  "payload": { "channel_id": 7, "subs": 47000, "views": 2300000 },
  "ts": "2026-05-20T14:23:30Z"
}

// Disconnect / error
{
  "kind": "error",
  "payload": { "message": "Cable disconnected", "code": "CABLE_DISCONNECT" },
  "ts": "2026-05-20T14:23:45Z"
}
```

### First-paint contract

Server-side render returns the layout shell with:

- Reserved dimensions per panel (min-width / min-height / aspect-ratio)
- Placeholder cells using `———` or `…` for unknown values
- Initial data EMBEDDED inline ONLY for above-the-fold panels (critical
  first-paint metrics)
- Below-the-fold panels render empty + subscribe via cable on
  intersection (lazy)
- Cable subscription kicks off on `turbo:load` for above-the-fold; on
  `IntersectionObserver` for below-the-fold

This gives instant first paint AND live updates.

### Error handling

- Cable connection lost: client retries every 5s for 30s, then surfaces
  an error indicator (`✗ disconnected` in the powerline synced slot)
- On reconnect: server replays the latest state push for every
  subscribed channel via cable's `subscribed` callback
- Subscribe rejection (auth failure): client logs out + redirects to
  login
- Payload parse failure: client logs to console, indicator stays in
  last-known state, server diagnostic written

### Ratatui client contract

The Rust Ratatui client uses the SAME cable channels via a Rust
ActionCable client library. Same payload schema. Same kinds. Same
channel names.

Differences:

- Ratatui renders text + ASCII directly to terminal (no DOM)
- No first-paint shell — Ratatui starts empty and subscribes immediately
- Same Stimulus-like state machine per panel (Rust struct holding
  current `kind` + last payload)

### Authentication / authorization

- Cable connection authenticated via the same session cookie as HTTP
  (Devise/Rails session)
- Per-channel authorization in `subscribed` callback of each Channel
  class:
  - Global channels (`pito:powerline:*`): any authenticated user
  - Per-channel scope (`pito:channels:<id>:*`): user must be owner OR
    shared
  - Per-game / per-bundle scope: user must be owner
  - Settings panels (`pito:settings:*`): user must be authenticated
    (anyone can see their own)
- Unauthorized subscribe → reject + log

### Sidekiq integration

Cable payloads triggered by:

1. `after_perform` hook on every Sidekiq job → broadcasts queue depth
   update to `pito:powerline:sidekiq`
2. Sidekiq middleware (Sidekiq Pro? sidekiq-status?) emits progress
   events for long-running jobs → broadcasts `progress` payloads to
   relevant panel channels
3. Sidekiq retries → broadcasts `error` payload with retry count

### Phase F1 implementation order

| Step | Scope                                                       | File                                                    |
| ---- | ----------------------------------------------------------- | ------------------------------------------------------- |
| 1    | Define base `ApplicationCable::Channel` + auth              | `app/channels/application_cable/channel.rb`             |
| 2    | Define `PowerlineSyncedChannel`, `PowerlineSidekiqChannel`  | `app/channels/powerline_*.rb`                           |
| 3    | Define `cable-panel` Stimulus controller                    | `app/javascript/controllers/cable_panel_controller.js`  |
| 4    | Wire Sidekiq middleware for queue stats broadcast           | `config/initializers/sidekiq.rb`                        |
| 5    | Add specs for each channel + controller                     | `spec/channels/*`, `spec/javascript/controllers/cable_panel_*` |

Other panels (per-channel, per-game) added in F4/F5.

## Consequences

- Every ViewComponent that needs live data declares its channel via
  `data-cable-channel`
- Server emits broadcasts at well-defined hook points; client subscribes
  and re-renders
- Ratatui parity from day one (same channels, same payloads)
- No SSE / polling — all updates flow via cable
- Initial bundle Sidekiq integration requires `Sidekiq.middleware` hook
  in `config/initializers/sidekiq.rb` (server side)

## Alternatives considered

- **SSE / EventSource**: rejected. Cable is more bidirectional +
  supports unsubscribe natively + has existing Rails infrastructure.
- **One global channel for everything**: rejected. Per-panel scope is
  cleaner; subscription auth is easier per-channel.
- **No initial data inline (pure cable populate)**: rejected.
  First-paint feels broken without inline data for above-the-fold
  panels.

## Date

2026-05-20

## Related

- ADR 0016 — TUI design system and cable-first architecture (declared
  the direction)
- ADR 0015 — Theme system mathematical derivation (preserved)
- `docs/architecture.md` — overall topology (Phase F8 update target)
