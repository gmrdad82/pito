## 2026-05-11 — `connected` derived-surface unwind

**What:** Drop the `connected` boolean as a derived surface across the app —
`Channel.connected` scope, `ChannelDecorator#connected` field, MCP `connected`
filter, picker connected/disconnected chip, factory `:connected` trait, and the
`[connect]` / `[disconnect]` action links. The DB column remains for now;
everything that exposed `connected` as a user-facing or query-facing surface is
gone.

**Why:** Post-OAuth, every channel is connected by definition — the binary state
is dead semantic weight. This was Phase 7 Path A2 residue that survived as a
derived scope until now.

**Where:** Commit `e597ab3` (2026-05-11) "Drop derived 'connected' surface
app-wide (scope, decorator field, MCP filter, picker chip, views, keymap)".
