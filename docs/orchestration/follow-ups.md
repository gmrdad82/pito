# Follow-ups — deferred items tracked across phases

This file lists work items the architect or user has explicitly deferred — items
that should be picked up at a specified trigger condition, not now. Each item
names the trigger so it doesn't get lost.

When the trigger condition fires, a small dedicated agent should be dispatched
to handle the cleanup, run gates, and report. Once the item ships and commits,
mark it Done with the commit reference.

## Open

### Channel Revamp post-commit cleanup

**Trigger:** after Channel Revamp phase commits have landed on `main` across all
repos AND the user confirms the phase is closed (testing complete, validation
done).

**Items:**

1. Delete `pito/app/views/shared/_confirm_dialog.html.erb` — orphaned generic
   confirm dialog from Alpha. The May 2 2026 grep confirmed no callers anywhere.
2. Delete `pito/app/javascript/controllers/confirm_dialog_controller.js` —
   companion Stimulus controller. No `data-controller="confirm-dialog"`
   references in any view.
3. Remove the `confirm:` kwarg from
   `pito/app/components/bracketed_link_component.rb` — currently
   accepted-but-ignored after the modal refactor; no call sites use it. Update
   specs accordingly.

**Verification before deletion:**

- Re-run the grep used during the modal refactor to confirm continued orphanage:
  - `grep -rn "_confirm_dialog\|confirm_dialog_controller\|data-controller=\"confirm-dialog\"" app/`
  - Should return zero matches.
- After deletion: full RSpec suite + Brakeman remain green.

**Commit message suggestion:** `Remove orphaned confirm-dialog primitives`

### Rails-app keyboard shortcuts

**Trigger:** future phase, after Channel Revamp commits land. Could be folded
into a broader "polish / accessibility" phase or a dedicated "keyboard
navigation" phase.

**Items:**

The Pito Rails web app should adopt the same keyboard shortcut schema as the
`pito` CLI. The CLI dictates the canonical shortcuts; the web app follows.
Specifically:

1. Add a `?` keyboard binding to the web app that opens a keyboard-shortcuts
   modal. The modal lists all bindings grouped by section (general, navigation,
   channels list, channel detail, confirmation prompts, etc.) — same sections as
   the `pito` CLI's help dialog.
2. Add a visible `?` button at the top-right of every page, near the theme
   switcher. Clicking it opens the same modal as pressing `?`.
3. Implement the keyboard bindings themselves:
   - `?` — toggle help modal
   - `q` — back / close
   - `g d` / `g c` / `g v` / `g s` / `g e` — navigate to dashboard / channels /
     videos / saved views / settings
   - `n` — toggle dark/light theme
   - `/` — open search (focus the existing search input)
   - `j` / `k` — down / up in tables
   - `space` — toggle bulk select on highlighted row, ONLY when bulk mode is on
     (clicking `[bulk]` first). When bulk mode is off, `space` is a silent
     no-op. Mirrors the `pito` CLI's gated behavior.
   - `b` — toggle bulk mode
   - `s` — toggle star on highlighted row
   - `c` — toggle connected on highlighted row
   - `D` — delete selection (or current row)
   - `Y` — sync selection (or current row)
   - `f s` / `f c` / `f y` — filter chips toggle (starred / connected / syncing)
   - `v` — view URL in browser (channel detail)
   - `y` — confirm in confirmation dialogs
   - `Esc` / any other key — cancel in confirmation dialogs

Mirror the exact key bindings used in the `pito` CLI (verify by reading
`extras/cli/src/keys.rs` and `extras/cli/src/ui/help.rs` at the time of
implementation).

4. The shortcuts must NOT conflict with browser-level shortcuts (e.g., `Ctrl+F`
   for search stays browser; the in-app `/` opens the app's search input). Test
   with screen-reader compatibility.

5. Stimulus controller(s) handle the global key listener and the per-screen
   behaviors. Multi-key sequences like `g d` need a state machine (similar to
   vim's leader-key prefix).

6. The modal that opens for `?` reuses or mirrors the `ConfirmModalComponent`
   styling — match the design system. Lists the bindings in the same grouping as
   the `pito` CLI's help screen.

**Verification before implementation:**

- Read the `pito` CLI's keyboard schema at the time of implementation
  (specifically `extras/cli/src/keys.rs` and `extras/cli/src/ui/help.rs`) to
  capture any updated bindings.
- Confirm with the user that the schema is still desired before coding.

### `pito` CLI screen layout parity with Rails app

**Trigger:** any future phase that touches a `pito` CLI screen, OR a dedicated
polish pass after the current phase commits.

**Items:**

The `pito` CLI (`extras/cli/`) and the Rails web app should mirror each other in
screen layout, link placement, and which links/actions are available where. The
Rails app dictates the canonical layout; the `pito` CLI follows.

Known discrepancies as of 2026-05-03 (Channel Revamp validation):

1. **Channel detail screen — top action legend:** the `pito` CLI currently shows
   `[view] [sync] [delete]   (v) view  (Y) sync  (D) delete  (s) star` at the
   top. Web shows only `[view] [sync] [delete]` in the breadcrumb actions. The
   `(s) star` keystroke hint should NOT appear at the top — star/unstar lives
   inline on the Starred row (mirrors web's `[star] / [unstar]` button on the
   Starred KV row).

2. **Sync link placement:** verify the `pito` CLI's `[sync]` button placement
   matches web's. Web has `[sync]` in the breadcrumb actions row. The CLI should
   match.

3. **Other discrepancies:** sweep every screen — channels list, channel detail,
   videos list, video detail, dashboard, search, settings — and surface every
   layout/link mismatch. Document each in this entry as a sub-bullet before
   fixing.

**Implementation strategy:**

- Read the corresponding Rails ERB views first; they're the spec.
- Map each Rails action / link / data display to the `pito` CLI equivalent.
- Where the `pito` CLI diverges (extra hints, missing actions, different
  placement), align to Rails.
- Where the divergence is intentional (e.g., terminal-only keystroke hints in
  the help screen), document and keep.
- One Stimulus-style "actions row" matches one TUI "breadcrumb actions" line.
  One inline button matches one inline keystroke hint, etc.

**Verification before implementation:**

- Open both surfaces side-by-side. Take screenshots of each Rails screen + the
  matching `pito` CLI screen.
- Diff them mentally / on paper.
- Confirm the spec captures every discrepancy before dispatching the
  implementer.

**Out of scope for this follow-up:**

- Adding NEW features to either side (e.g., implementing keyboard shortcuts in
  Rails — that's the separate "Rails-app keyboard shortcuts" follow-up).
- Refactoring the visual design system itself.
- Adding screens that don't yet exist on one side.

This follow-up is about parity, not feature parity. It strictly aligns the
EXISTING screens.

### `pito` CLI Dependabot alert #1 (low severity)

**Trigger:** the next time the `pito` CLI is touched, OR a dedicated
dependency-hygiene pass.

**Items:**

GitHub Dependabot flagged 1 low-severity vulnerability on the `pito` repo's
default branch after the Channel Revamp commit (`0e096b7`), originating from the
Rust crates under `extras/cli/`. Surfaced via the `git push` warning:

```
remote: GitHub found 1 vulnerability on gmrdad82/pito's default branch (1 low).
remote:      https://github.com/gmrdad82/pito/security/dependabot/1
```

**Actions:**

1. Visit the Dependabot alert in the `pito` repo's Security tab to identify the
   vulnerable crate and the recommended fix version.
2. Bump the affected dependency in `extras/cli/Cargo.toml` to the patched
   version. Run `cargo update` to refresh `Cargo.lock`.
3. `cargo check --all-targets` and `cargo test` must pass after the bump.
4. Commit + push to `main`. Verify the alert clears on GitHub.

**Note:** low severity, not blocking — but worth clearing during normal dev
hygiene rather than letting it sit. Same approach for any future Dependabot
alerts on the `pito` repo.

## Done

(Items move here after they ship, with commit hash + date.)
