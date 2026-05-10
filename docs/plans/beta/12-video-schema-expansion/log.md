# Phase 12 — Video Schema Expansion + Edit Surface + Pre-Publish Checklist

> Phase log. Newest entries on top once sessions land.

## Stub

Phase folder created on 2026-05-10 by architect-spec to hold:

- `specs/01-video-schema-expansion-and-pre-publish-checklist.md` — first (and
  currently only) implementation spec for this phase. Covers schema expansion
  per Mobile notes 1 + 2, edit surface, pre-publish checklist modal, sync-back
  to YouTube via `videos.update`, direct `Video.project_id` linkage (replaces
  the dropped Timeline model).

Cross-references when work begins:

- `docs/realignment-2026-05-09.md` — work unit 4. Resolved ambiguities #1
  (Timeline drop → `Video.project_id`), #7 (checklist on publish/schedule only),
  #10 (Path A2 retired).
- `docs/notes/2026-05-09-17-56-06-video-model-youtube-api.md` (Note 1).
- `docs/notes/2026-05-09-18-02-30-video-model-addendum-end-screen.md` (Note 2).
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — inherited
  destructive-and-reseed migration posture (note: by the time this phase ships,
  Phase 8 has already reseeded; this phase migrates additively).
- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` —
  `YoutubeConnection` model identifier post-Phase-9.
- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
  — schema baseline this phase builds on.
- `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
  — `youtube_connection_id` foreign key naming this phase inherits.

## Sessions

(none yet)
