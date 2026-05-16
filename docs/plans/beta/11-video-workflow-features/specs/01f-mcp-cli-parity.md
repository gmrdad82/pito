# 01f — MCP + CLI Parity (docs-only follow-up)

> Parent: `docs/plans/beta/11-video-workflow-features/plan.md`. **No
> implementation lanes dispatched.** This sub-spec is a registry of the MCP tool
> surface that would correspond to each Phase 11 web slice, with the CLI half
> deferred per the active MCP/TUI pause.
>
> Cross-reference once the pause lifts: `docs/orchestration/follow-ups.md` → CLI
> feature-parity sweep + MCP parity entries.

---

## Goal

Capture, without dispatching, the MCP tool surface for each Phase 11 web slice
(`01a` / `01b` / `01c` / `01d` / `01e`). When the MCP/TUI pause lifts, this
document becomes the architect-handoff for the implementation lanes. The capture
covers tool name, arguments, return shape, and the yes/no boundary at every
external Boolean.

---

## Files touched

**This sub-spec writes nothing under `app/`, `lib/`, `db/`, `spec/`, or
`extras/`.** It only lives in `docs/plans/beta/11-video-workflow-features/`.

The eventual implementation lanes would touch:

- `app/mcp/pito_mcp/tools/` — new tool classes.
- `app/mcp/pito_mcp/dispatchers/` — if a dispatcher pattern is in use for the
  existing tool families.
- `spec/mcp/` — tool specs covering happy / sad / edge / flaw + yes/no boundary
  coercion.
- `extras/cli/` — Rust CLI surface lifting these tools into the TUI.

None of those files are touched by this sub-spec.

---

## MCP tool surface — captured per slice

### From `01a` — Edit page polish

#### `video_chapters_list`

Read a video's chapters.

- Args: `youtube_video_id: string`.
- Returns: `{ chapters: [{ id, start_seconds, label, position }] }`.
- Scope: `app`.

#### `video_chapters_set`

Replace a video's chapters in one call (idempotent upsert + delete-missing).

- Args:
  ```json
  {
    "youtube_video_id": "string",
    "chapters": [
      { "start_seconds": 0, "label": "Intro" },
      { "start_seconds": 120, "label": "Setup" }
    ],
    "confirm": "yes" | "no"
  }
  ```
- `confirm` is yes/no per CLAUDE.md hard rule (two-step destructive semantics).
- Returns: `{ ok: "yes", chapters: [...] }` on success.

#### `video_end_screens_list` / `video_end_screens_set`

Same shape as chapters. `kind` arg restricted to
`"related_video" | "related_channel" | "related_playlist" | "none"`.

### From `01b` — Pre-publish checklist expansion

#### `video_checks_list`

Read the nine checks' current state for a video.

- Args: `youtube_video_id: string`.
- Returns:
  ```json
  {
    "checks": [
      {
        "key": "thumbnail_attached",
        "passed": "yes" | "no",
        "skipped": "yes" | "no",
        "skip_rationale": "string | null",
        "manual": "yes" | "no"
      }
    ],
    "all_passed": "yes" | "no"
  }
  ```

#### `video_checks_skip`

Skip a failing check with rationale (upsert).

- Args:
  ```json
  {
    "youtube_video_id": "string",
    "check_key": "string",
    "rationale": "string",
    "confirm": "yes" | "no"
  }
  ```
- `confirm` is yes/no.
- Returns: `{ ok: "yes", check_key, rationale }`.

### From `01c` — Post-publish workflow

#### `video_post_publish_cadence_get` / `video_post_publish_cadence_set`

Read or set the cadence — install-wide default OR per-channel override.

- Set args:
  ```json
  {
    "scope": "app" | "channel",
    "channel_id": "int (required when scope=channel)",
    "comments_window_hours": "int (>= 1, null clears the override)",
    "analytics_window_days": "int (>= 1, null clears the override)",
    "confirm": "yes" | "no"
  }
  ```
- Returns:
  `{ ok: "yes", effective_comments_window_hours, effective_analytics_window_days }`.

### From `01d` — Series / sequel tracking

#### `video_series_attach`

Attach a video to a series parent.

- Args:
  ```json
  {
    "youtube_video_id": "string (member)",
    "parent_youtube_video_id": "string",
    "part_number": "int | null",
    "confirm": "yes" | "no"
  }
  ```

#### `video_series_detach`

Detach (`series_parent_id = nil`).

- Args:
  ```json
  {
    "youtube_video_id": "string",
    "confirm": "yes" | "no"
  }
  ```

#### `series_show`

Read a series.

- Args: `id: int`.
- Returns: `{ series_parent: {...}, members: [{...}, ...] }`.

### From `01e` — Video LINKS

#### `video_links_list` / `video_links_set`

Same shape as `01a` chapters / end-screens. `kind` restricted to
`"related_video" | "related_channel" | "external_resource" | "sponsor"`.

---

## CLI half (deferred)

The `pito` CLI (Rust + Ratatui) is paused per the active MCP/TUI pause. When the
pause lifts, the CLI lanes:

1. **TUI Video Edit pane.** Mirror the web edit-pane sub-sections — thumbnail
   (upload path TBD on the CLI side), tags, chapters, end-screens, links. Each
   sub-section is a sub-pane the user can tab through with `j` / `k` navigation.
2. **TUI Pre-publish modal.** Render the nine-check list with status
   indicators + a `[s]` keybind to enter a skip-rationale overlay.
3. **TUI Post-publish cadence settings.** Surface the install + per-channel
   defaults as edit-in-place number fields.
4. **TUI Series picker.** Typeahead picker mirroring the web edit surface —
   search by title, cap 20 results, attach / detach primitives.
5. **TUI Video Links section.** Mirror the four-kind grouped editor.

All CLI lanes consume the MCP tool surface defined above. No direct Rails DB
access from the CLI.

---

## Acceptance

This sub-spec ships as documentation only. The acceptance is:

- [ ] The captured tool surface above is reviewed by the master agent and either
      accepted (then this file is the source-of-truth when the pause lifts) or
      amended in place.
- [ ] A follow-up entry lands in `docs/orchestration/follow-ups.md` referencing
      this file as the architect-handoff for the eventual MCP + CLI parity
      lanes.
- [ ] No code lanes are dispatched as part of `01f`.

---

## Manual test recipe

N/A — docs-only.

---

## Cross-stack scope

| Surface            | Status                             |
| ------------------ | ---------------------------------- |
| Rails web          | OUT OF SCOPE                       |
| Rails MCP          | CAPTURED — implementation deferred |
| `pito` CLI (Rust)  | CAPTURED — implementation deferred |
| Cloudflare website | OUT OF SCOPE                       |

---

## Open questions

1. **Tool scope.** Parent locked decision §15 → `app` scope for every tool.
   Surface for user lock if any tool needs `dev` instead (architect cannot think
   of one in v1).
2. **`confirm: yes/no` granularity.** Every destructive / mutating tool carries
   `confirm: "yes" | "no"` per CLAUDE.md. Read-only tools (`*_list`, `*_get`,
   `series_show`) do not.
3. **CLI pause lift signal.** Surface for user direction — what's the trigger to
   lift the pause? Architect proposes "once the web surface for Phase 11 is
   validated in production by the user for ≥2 weeks."
4. **Tool naming consistency.** The Phase 27 / 28 surface uses
   `game_update_local`, `games_list`, `game_show`. Phase 11 uses
   `video_chapters_*`, `video_end_screens_*`, `video_links_*` (plural resource
   embedded in the tool name). Confirm the naming style is acceptable —
   alternative is `video_update_local` taking nested `chapters` / `end_screens`
   / `links` arrays as a single call.
