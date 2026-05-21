# TUI — Rust client

## Status

The Rust `pito` binary at `extras/cli/` is **planned**. Foundation work
and proof-of-concept code exists. Full implementation begins after the
web surfaces stabilize on the locked architecture.

**Scope:** TUI = 100% of what the web app does. Every screen, panel,
sub-panel that the web renders, the TUI renders too. The Rust client
is the canonical alternative interface to the same Rails backend.

## Process model

Single binary at `extras/cli/`. Style mirrors the `claude` binary:

- `pito` (no args) — launches the TUI
- `pito footage <args>` — footage upload subcommand
- `pito help` — help text
- `pito version` — version info
- More subcommands as needed

## Surface contract

The TUI renders the same 3 screens as the web app:

- `/` Home (dashboard + system monitoring) — Dracula Purple `#bd93f9`
- `/videos` (channels + videos) — Dracula Red `#ff5555`
- `/games` (catalog + bundles + footage) — Pale Cobalt `#7eb6ff`

Layout chrome (TST + content + BST) is identical. The 3 accents drive
Ratatui `Style` calls the same way they drive CSS custom properties on
the web.

**Visual parity goal:** someone fluent in the web app should not need
to re-learn the TUI. Same panels, same sub-panels, same focusables,
same keybindings, same actions, same copy.

## Authentication

OAuth2-via-browser fallback. The TUI cannot complete an OAuth2 flow
itself; it opens the browser, waits for the redirect callback, and
caches the resulting token in `~/.config/pito/credentials.toml`.

The cached bearer token authenticates subsequent API calls. Token
refresh follows the same flow as the web app.

When the TUI hits ANY operation it can't complete (OAuth2, captcha,
arbitrary web flow), it falls back to opening the browser and resumes
once the browser flow completes.

## Keybindings

Identical to the web app with **one exception**: `q` quits the TUI.
No web equivalent.

All other keys (j / k / h / l / Tab / Shift-Tab / Ctrl-h/j/k/l / i /
Esc / SPACE / `?` / `:` / `s` / `S` / Enter) behave identically.

Key labels come from the shared i18n YAML
(`config/locales/keybindings/en.yml`). The TUI reads the same YAML the
web app does.

## Cable subscription

The TUI subscribes to the same `pito:*` cable channels as the web client.
The payload format is identical (`{ kind, payload, ts }`). Bridge via
the Rails WebSocket.

When the TUI subscribes to `pito:status_bar`, the same data that paints
the web TST paints the TUI TST. Same for panel + sub-panel streams.

## Screen export

A rake task at `lib/tasks/pito_tui_export.rake` (forward plan) reads:

- Panel VC class definitions + their spec assertions
- Panel VC class-level docblock headers (kwargs, focusables, CABLE_CHANNEL,
  keybinds, sub-panel composition)
- `Pito::Theme::Sections` tokens
- `config/locales/**.yml`
- `docs/design.md` locks (terminology, brand caps, mode model)
- `config/keybindings.yml`

And emits per-screen + per-panel TOML specs at
`extras/cli/src/screens/specs/<screen>/<panel>.toml`. The Rust client
`include_str!`s these at compile time and `serde`-deserializes them
into `PanelSpec` structs. Ratatui rendering follows the spec.

This is the canonical way the TUI stays in sync with the web app. When
a panel VC changes shape, the rake task picks it up and the TUI gets
the new contract without manual porting.

**Why every panel VC must have a docblock + focusables + CABLE_CHANNEL
+ keybinds:** the rake task parses these to derive the panel spec.
A panel VC without them blocks TUI re-export.

## Action bus integration

The TUI invokes the action bus via the Ruby dispatcher (in-process when
embedded as a daemon, or via HTTP when remote):

```rust
pito::action::dispatch("reindex_meilisearch", params)
```

Under the hood this hits `Pito::ActionDispatcher` on the Rails side.
Same confirmation flow as the web (two-step `confirm: bool` for
destructive actions). Same `204 no_content` response + cable broadcast
for UI updates.

## Cross-stack parity tests

For each pure formatter / cell-producer (`Tui::SegmentedBarComponent`,
`Tui::ShadedDensityComponent`, sparkline helpers, `Pito::Formatter::*`),
the Rust crate has an equivalent function with the same name and
input/output.

A `cargo test` feeds known inputs (percent values, byte counts, ISO
dates) and asserts the Rust output equals the Ruby component's rendered
output (captured as fixture at rake export time).

This catches drift between the two stacks before it ships.

## Wire format

Same as MCP: `yes` / `no` for booleans, JSON envelopes, cursor
pagination.

## Theme export

`lib/tasks/pito_theme.rake` emits `extras/cli/src/theme.rs` from
`Pito::Theme::SEMANTIC`. The Rust `Theme` struct is the canonical
binding for Ratatui `Style` calls.

## Forward plan

When TUI work picks up:

1. Add `lib/tasks/pito_tui_export.rake` skeleton (rake stub that emits a
   first panel's TOML — proof of concept).
2. Add `extras/cli/src/spec.rs` with `serde` `PanelSpec` struct.
3. Implement TUI rendering of `Pito::SecurityPanelComponent` (the
   ex-settings security panel, now on Home) as the first end-to-end
   panel.
4. Expand to remaining screens (Videos, Games).
5. Add cross-stack parity tests in `cargo test`.

Until then: the binary builds, basic subcommands work, no TUI rendering
yet.
