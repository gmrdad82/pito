# Video upload — reuse info from previous videos (future feature)

Captured for the future video-upload phase (currently slated as a follow-up to
Phase 22 import, separate from import).

## What

When uploading a new video, mirror YouTube Studio's "reuse info" feature: let
the user pick a previously-uploaded video from the same channel and pre-fill
the new video's:

- title
- playlist membership
- description
- tags
- category

Per-field opt-in (checkbox per field) — not all-or-nothing. The user picks the
source video first, then ticks which fields to carry over, then edits whatever
they want before submit.

## Why

Existing pito differentiator: managing multiple channels + multi-channel
parallel uploads. "Reuse info" reduces the friction of getting consistent
metadata across a channel's catalogue, especially for series content where
titles + descriptions follow templates.

## When

After the video-upload entry-point spec lands (Phase 22 §1 said `+ new (upload
flow)` on the Videos submenu — that flow's spec hasn't been written yet).

This note is the kernel for that future spec's "reuse info" section.
</content>
</invoke>