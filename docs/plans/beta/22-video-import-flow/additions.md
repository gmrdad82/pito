## 2026-05-11 — Phase sourced from Mobile note

**What:** Phase 22 (video-import-flow) was sourced from the 2026-05-11 Mobile
note, specifically section B6.

**Why:** Provenance — record where the phase's scope came from so the plan /
spec lineage stays auditable.

**Where:** Source note —
`docs/notes/2026-05-10-22-29-58-reply-to-keybindings-and-future-development.md`,
section B6.

## 2026-05-11 — Out-of-scope adjacent: future video-upload flow

**What:** Phase 22 §1 mentioned `+ new (upload flow)` on the Videos submenu, but
the upload flow itself is out of scope for Phase 22 (import only). A future
phase will own the upload entry point and its spec.

**Why:** Distinguishes "import an existing YouTube video into pito" (Phase 22)
from "upload a brand-new video to YouTube via pito" (future). The two share UI
real estate on the Videos submenu but are different workflows.

**Future spec kernel — reuse info from previous videos.** When the upload-flow
spec is written, it should include a "reuse info" feature mirroring YouTube
Studio: let the user pick a previously-uploaded video from the same channel and
pre-fill the new video's title, playlist membership, description, tags, and
category. Per-field opt-in (checkbox per field) — not all-or-nothing. The user
picks the source video first, then ticks which fields to carry over, then edits
whatever they want before submit. Rationale: pito already differentiates on
multi-channel parallel uploads; reuse-info reduces friction for series content
where metadata follows templates across a channel's catalogue.

**Driver:**
`docs/notes/2026-05-11-14-50-00-video-upload-reuse-info-from-previous-videos.md`
(captured 2026-05-11, folded here and dropped).
