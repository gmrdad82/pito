# Reply to keybindings + future development (2026-05-11)

Reply to `docs/notes/2026-05-10-23-30-00-keybindings-unified-schema-proposal.md`.
Two parts: (A) keybinding revisions, (B) broader product direction beyond
keybindings.

---

## A. Keybinding revisions

### 1. Drop bulk-mode toggle

We'll have bulk operations but **no bulk-mode toggle**. The `b` binding is
removed across all surfaces. Bulk operations (`-` delete, `s` sync, `r` resync)
remain in the menu and operate on whatever selection state the page exposes
natively — no separate mode switch.

Affected submenus:

- Channels: drop `b`. Keep `l +  - s`.
- Videos: drop `b`. Keep `l -`.
- Projects: drop `b`. Keep `l + -`.
- Games: drop `b`. Keep `l + - r B`.
- Bundles: unchanged (no `b` was there).

### 2. Filters — `f` everywhere with a sub-scheme

Anywhere a page exposes filters, the leader menu reserves `f` for filter, and
opens a sub-scheme covering the filter options available on that surface.

Pattern: `f <filter-key>` toggles / sets that filter. Example shape (channels):

```
f filters ->
  s starred
  c connected
  d disconnected
  x clear all
```

The exact filter keys are per-surface and will be specced when each surface's
filters are finalized. The contract is: every filterable page exposes `f`.

### 3. Sorts — `s` everywhere with a sub-scheme

Same pattern for sort. Reserve `s` for sort, sub-scheme covers possible sorts
on that surface.

```
s sort ->
  n name
  d date
  v views
  r reverse current
```

Conflict note: `s` is currently used at Channels root for "bulk sync." That
collision needs resolving — proposal: move bulk sync under a `o` (operations)
or simply `S` (capital), and keep lowercase `s` reserved globally for sort.
Flagging for review before schema lock.

### 4. Multiple tables on one page — extra nesting

When a surface has more than one table/list, `f` and `s` add an extra level to
select the target table first, then the filter/sort key. Shape:

```
f filters ->
  1 <table-1-label> -> <filter sub-scheme>
  2 <table-2-label> -> <filter sub-scheme>
```

Pages with a single table skip that level — `f` opens the filter sub-scheme
directly. The renderer decides at runtime based on how many filterable tables
the page declares.

### 5. Split views — `|` in the menu

Split-view toggle binds to `|`. Add it to the root menu (or per-surface where
split applies, TBD). Visual: appears as `| split` in the popup. Closes split
when pressed again.

### 6. Analytics — not covered now

Confirmed: analytics stays out of the leader menu for now. Per-context access
via channel/video show pages, as the original proposal had it.

### Updated root menu (after revisions)

```
h home
c calendar       -> calendar submenu
C channels       -> channels submenu
V videos         -> videos submenu
P projects       -> projects submenu
G games          -> games submenu
N notifications  -> notifications submenu
S settings       -> direct nav
/ search         -> search submenu
| split toggle
q quit (TUI only)
Q quit + logout
```

`f` and `s` are not at the root — they're per-surface, surfaced inside each
submenu where filters/sorts apply.

### Open conflict to resolve

- Channels `s` bulk sync vs global `s` sort. Pick one before schema lock.

---

## B. Beyond keybindings — product direction

### B1. Videos can be added (not only synced) — bring `+` back

Reverse the earlier decision. Videos get a `+` binding because **pito will
support uploading videos**, not just syncing them from YouTube.

Core differentiator restated: pito lets me manage multiple channels and upload
two videos at the same time — one to channel A, one to channel B — without
having to juggle two YouTube Studio windows logged into two different channels.
This is one of the main reasons pito exists.

Videos submenu becomes:

```
l list
+ new (upload flow)
- bulk delete
```

(plus `f` / `s` per the keybinding revisions above)

The upload flow itself is a separate spec — capturing here that the binding
and the affordance need to exist.

### B2. Daily sync produces diffs + notifications

Both channels and videos run a daily sync that **checks for diffs** between
pito state and YouTube state. When a diff is detected:

- A notification is produced (feeds into the existing notifications surface).
- A **diff dialog** is presented for reconciliation.

This is the day-to-day mechanism for keeping pito and YouTube aligned without
silent overwrites in either direction.

### B3. Sync never overwrites — it produces a diff dialog

**Critical**: the sync action for channels and videos does **not** overwrite
pito state, and does **not** push to YouTube. It produces a **diff dialog**
that I reconcile manually.

This applies to:

- The daily background sync (B2).
- The user-triggered `s` (or whatever it becomes) sync action.

Reconciliation directions:

- Accept YouTube → pito (pull change in).
- Accept pito → YouTube (push change out).
- Ignore (leave both as-is, optionally mark as expected divergence).

Per-field granularity in the diff dialog (title, description, tags, category,
privacy, etc.) — accept some fields, reject others.

This needs to land in the model layer before we wire the menu actions to
backend behavior. Important enough to call out as a blocking design decision
for any Step that touches channel/video sync.

### B4. Games — defer custom add, IGDB-only for now

Games can be added as currently implemented: via IGDB. When I hit a game that
IGDB doesn't cover, I'll deal with it then. **Defer custom game add to future.**

No changes to the Games submenu beyond the bulk-toggle removal in A1.

### B5. Screen review pass — needs clean DB

Start reviewing screens — specifically channels and videos — so they're
properly displayed. To do this productively I want the DB **reset to just the
settings**: no channels, no videos, no projects, no games.

Workflow:

1. Reset DB to settings-only.
2. I connect my real YouTube channels and import real videos.
3. We capture those rows as **seed data** for future development.

This becomes the baseline seed set going forward, replacing any placeholder /
factory data we currently use for dev.

Action item: add a rake task (or equivalent) that nukes everything except
`settings` and whatever the auth/user row needs to be. Then a separate task to
dump current DB state as seeds once I've connected my real channels.

### B6. Videos import flow — full spec

Introduce `[import]` on `/videos`. This is a first-class affordance, not just
a binding.

#### Entry point

- On `/videos`, an `[import]` button is visible alongside (or near) the existing
  controls.
- Clicking `[import]` opens a **modal**, NOT a navigation.

Correction to my own earlier phrasing: I said "direct me to a screen" and then
"clicking it will open a modal." Going with **modal** — keeps the user on
`/videos` and matches how the progress + confirmation UI wants to behave.

#### Step 1 — channel selection

Inside the modal:

- Show all available channels (the ones connected to pito).
- Each channel has a **checkbox**.
- I tick the channels I want to import videos from.
- Confirm button kicks off the import.

#### Step 2 — background jobs

On confirm:

- A new **`ImportJob` model** is introduced.
- One `ImportJob` record is created **per channel** selected.
- A background job is enqueued **per channel** (not one job for the whole
  batch — one per channel, so they run independently and can fail/retry
  independently).

#### Step 3 — progress visibility

While imports are running:

- The `/videos` page modal (if open) shows progress.
- The **channel page** also shows that an import job is ongoing, with a way to
  see its progress (link, badge, or inline indicator — TBD).
- Clicking `[import]` while a job is ongoing reopens the modal at the progress
  state.

Progress UI:

- Use our existing `=---` style indicator when granular progress isn't
  available yet.
- If we can compute detailed progress, show it: **how many videos will be
  imported, how many have been imported so far.** Per-channel breakdown.
- Detailed progress is "nice to have" — the `=---` indicator is the fallback.

#### Step 4 — scope of import

The import **only imports videos pito doesn't already know about**. We diff
against existing `Video` rows for that channel before pulling. Already-known
videos are skipped silently.

#### Step 5 — post-import confirmation table

When the import completes, the modal swaps the progress UI for a **table**:

Columns:

- Checkbox (all checked by default)
- Title
- Length
- Category

Behavior:

- All rows checked by default — I `[keep]` what I want.
- Unchecking a row means: that video gets **deleted from pito** when I confirm.
- Confirm button at the bottom (`[keep]` or similar).

#### Step 6 — graceful deletion + future-job safety

Critical implementation detail: when a video is unchecked and deleted from
pito after import, **future jobs that reference that video have to fail
gracefully**. The video is genuinely deleted from pito (not soft-deleted, not
hidden) and won't be re-imported by the next daily sync either — otherwise
we'd loop.

Implications:

- We need a **tombstone / exclusion list** so the daily sync knows "user
  explicitly rejected this YouTube video ID, don't re-import."
- Or: a "rejected at import" flag on a lightweight record. Design choice
  pending, but the behavior is non-negotiable: rejected videos stay rejected.
- Any job that has a `video_id` reference (analytics fetch, publish check,
  etc.) must handle `Video not found` without raising / paging.

#### Models / migrations needed

- `ImportJob`: belongs_to channel, status (queued / running / completed /
  failed), counters (`total_videos`, `imported_videos`), timestamps, optional
  error payload.
- Exclusion mechanism for rejected video IDs per channel (table or column TBD).
- `Video` deletion path must clean up associations cleanly.

#### Open questions on import (not blocking the spec, but worth noting)

- What does pito do if I tick a channel that already has an in-flight
  `ImportJob`? Likely: refuse / show "import already running."
- Does the post-import confirmation table support sort/filter (per the new
  `f`/`s` convention)? Probably yes once we standardize.
- Retention of `ImportJob` records — keep forever as audit trail, or expire?
  Lean toward keep forever.

---

## Dispatch priorities (my read)

Roughly in order:

1. **B5** — DB reset + seed workflow. Unblocks everything else because I can't
   review screens against junk data.
2. **B3** — sync-produces-diff design decision locked before any sync code
   touches production.
3. **A1–A6** — keybinding schema revisions, resolve the `s` conflict, lock
   `config/keybindings.yml`.
4. **B1** — videos `+` upload binding restored in schema (cheap; the actual
   upload flow is a later spec).
5. **B6** — `ImportJob` model + import modal flow. This is its own multi-step
   Phase.
6. **B2** — daily diff sync + notification wiring.
7. **B4** — games stay as-is.

User can re-rank.
