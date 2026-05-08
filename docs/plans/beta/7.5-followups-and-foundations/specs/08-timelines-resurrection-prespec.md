# Phase 7.5 — Step 08 — Timelines Resurrection (pre-spec)

> **PRE-SPEC.** Surfaces what the Timeline concept's current state is, what
> "resurrection" would mean, and the open questions the user must answer before
> a real implementation spec lands. No code dispatches off this doc as-is.

---

## What we have (rooted in code)

Timelines exist at the model level from Phase 4:

- `timelines` table (Phase 4 §3.6):
  `id, tenant_id, project_id, video_id (nullable), title, state (aasm enum: editing/exported/uploaded), duration_seconds, resolution, fps, export_filename, timestamps`.
- `Timeline` `belongs_to :project`, optional `belongs_to :video` (set when state
  moves to `uploaded`).
- State machine: `editing → exported → uploaded`. Phase 4 §11 describes the
  machine.
- Phase 4 deferred the actual UI / workflow surface; the table exists but the
  user-facing surface is minimal.
- Path A2 retracted Video metadata. Phase 4's
  `Timeline#link_or_create_video_for_upload` used to set
  `video.title = "Pending sync — …"`; that line was removed in Path A2 (the
  Phase 7 log notes the change). Today the timeline-to-video link is
  `youtube_video_id + channel` only.
- The Phase 4 master spec body has a §11 (state machine) and §12 (UX) for
  Timelines that was never fully implemented.
- `Confirmable::TYPES` includes `"timeline"`.

## What "resurrection" might mean

The user's wording — "Timelines: deferred from Phase 4. Resurrect properly OR
continue deferring." — frames two paths:

- **Resurrect** — flesh out the Timeline UI / workflow now (in 7.5 or a
  near-future phase).
- **Continue deferring** — keep the model on ice, do nothing, revisit later.

Things that "resurrection" might include:

- A `/projects/:id/timelines` pane on the project show page that lists timelines
  in editing/exported/uploaded states, with state transitions wired to bracketed
  actions.
- A Timeline show page with metadata + linked footage list + linked-video
  reference (when uploaded).
- Importer-side Timeline export: the user exports a timeline from their NLE
  (DaVinci Resolve / Premiere / kdenlive); a CLI subcommand
  (`pito timeline import` or similar) reads the export metadata file and creates
  a Timeline row with `state: exported`.
- Linkage from Timeline to YouTube Video: when the user uploads the rendered
  timeline to YouTube, the Timeline state moves to `uploaded` and links to a
  `Video` row (which Phase 8 will start populating with metadata).
- Timeline ↔ Footage relationship: which footage rows ended up in this timeline?
  Useful for "which clips have I used" queries.

## Open questions

**Q11.a — Resurrect or defer?** Big-picture call.

- (i) **Resurrect now (in 7.5 or 7.6).** Build the surface the user has been
  holding mental space for. Need Q11.b–e to scope.
- (ii) **Defer to Phase 9.** Phase 9 in the original beta plan was a
  video-workflow phase; Timelines fit naturally there.
- (iii) **Defer to Phase 11.** Phase 11 (Video Workflow Features) in the
  post-rework beta also fits.
- (iv) **Defer indefinitely.** Drop the Timeline concept; remove the `timelines`
  table. (The user's wording suggests this is unlikely, but it's a real option
  if the concept no longer fits.)

Master agent's lean: (ii) or (iii) — the YouTube data sync foundation (Phase 8)
is the gating prereq for Timeline ↔ Video linkage to be useful. Resurrecting
Timelines BEFORE Phase 8 means the uploaded-state half of the Timeline lifecycle
is still hollow.

If Q11.a = (i), continue:

**Q11.b — Importer-driven or web-driven?** Where does a Timeline row come from?

- Importer (CLI subcommand reads a Resolve / Premiere / kdenlive export).
  Mirror's the footage-import shape: ffprobe-equivalent for timeline metadata,
  JSON API to Rails.
- Web (user clicks `[ + new timeline ]` on the project show page, fills in
  title + footage selection + metadata).
- Both.

**Q11.c — Footage linkage.** Should Timelines hold a many-to-many to Footage
(which clips were used)? If yes, schema (a `timeline_footages` join table?) and
how it's populated (importer parses the NLE's media-list manifest? user manually
selects?).

**Q11.d — Video upload coupling.** When a Timeline transitions to `uploaded`,
does Pito orchestrate the YouTube upload (write scope needed — out of Phase 7 /
8 scope; Phase 10 territory), or does the user upload manually and Pito just
records the linkage post-hoc?

**Q11.e — Cross-stack surface.** CLI screen for Timeline list/detail? MCP tools
(`list_timelines`, `update_timeline`)? Rails-only?

## Master agent's lean

**Defer to Phase 9 or 11.** The Timeline lifecycle's headline value (linkage to
a real Video with synced metadata) needs Phase 8's data sync to land first.
Resurrecting Timelines BEFORE Phase 8 makes the uploaded state hollow. The Phase
4 footprint that exists (table + state machine + bare model) is fine to leave
as-is until the upstream phase is ready.

Captured here so the user can flip the lean if they want the UI now even with
the hollow uploaded-state.

## What happens next

After the user answers Q11.a:

- (i) — continue with Q11.b–e, then a follow-up architect-spec dispatch produces
  real implementation specs under `08b-timelines-<shape>.md`.
- (ii–iv) — close this pre-spec with a one-line pointer to the target phase or a
  deletion plan.

## Files touched

None in this pre-spec.

## Acceptance

- [ ] User answers Q11.a (and Q11.b–e if Q11.a = (i)).
- [ ] Master decides: real spec, defer, or drop.
- [ ] Follow-up architect dispatch (if applicable) produces the implementation
      spec; this file closes with a pointer.

## Manual test recipe

Not applicable. Pre-spec.

## Cross-stack scope

Decided once Q11.e is answered.

## Follow-ups created

None until answered.

## Decisions (locked)

- **The Phase 4 `timelines` table and state machine are settled.** This pre-spec
  does not propose ripping them out unless Q11.a = (iv) explicitly asks for the
  drop, in which case a separate drop-spec is dispatched.
- **No Timeline ↔ Video metadata coupling before Phase 8.** Path A2 retracted
  Video metadata; the Timeline → Video FK is intentionally
  `youtube_video_id + channel` only until Phase 8.
