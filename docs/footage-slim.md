# Slim Footage to `filename` + `duration_seconds`

> Status: in progress — branch `followup-smart-link` (PR #68).

## Sign-off

- [x] Drafted
- [x] Audited — approved by user in chat (confirmed the 6 columns to drop, incl. the rake task: "no more grading evaluation, aspect ratio, orientation, etc.").

## North star

`Footage` keeps only what's used: `game_id`, `filename` (unique per game — the
skip-if-imported key), and `duration_seconds`, plus timestamps. The six unused
columns are dropped from the DB and removed from the model, the ffprobe Probe
service, the rake task, the factory, specs, and comments. No runtime code reads
the dropped columns; pito copy needs no change.

## Locked decisions

| Topic            | Decision                                                                                      |
| ---------------- | --------------------------------------------------------------------------------------------- |
| Columns dropped  | `resolution`, `fps`, `aspect_ratio`, `orientation`, `needs_grading`, `audio_track_names`.     |
| Columns kept     | `game_id`, `filename` (+ unique `[game_id, filename]` index), `duration_seconds`, timestamps. |
| Probe output     | `Probe::Result` slims to `duration_seconds, success, error_message` (also drops `bit_depth`). |
| Rake upsert      | `{ game_id, filename, duration_seconds, updated_at }` only.                                   |
| Migration        | Reversible `remove_column` (with original types) so `down` restores. Footage rows preserved.  |
| ffprobe fixtures | Unchanged (real ffprobe JSON; extra fields simply ignored now).                               |
| Pito copy        | No change (no footage-column-specific copy).                                                  |
| Branch           | `followup-smart-link` (PR #68). Do NOT merge — hold for the user's manual validation.         |

## Phase index

- P0 — Drop columns end-to-end (migration → model → probe → rake → factory → specs).

## P0 — Slim Footage

- [x] T0.1 Generate a reversible migration `db/migrate/*_drop_unused_footage_columns.rb` removing `resolution`, `fps`, `aspect_ratio`, `orientation`, `needs_grading`, `audio_track_names` via `remove_column` with their original types/options. complexity: [low]
- [x] T0.2 Run `bin/rails db:migrate`; confirm `db/schema.rb` shows the 6 columns gone and the unique `[game_id, filename]` index intact. complexity: [low]
- [x] T0.3 Slim `app/models/footage.rb`: remove the `ORIENTATIONS` constant, the `orientation` inclusion validation, and the `audio_track_count` method; keep `belongs_to :game` + filename presence/uniqueness. complexity: [low]
- [x] T0.4 Slim `app/services/pito/footage/probe.rb`: reduce `Result` to `duration_seconds, success, error_message`; delete `eval_fps`, `infer_bit_depth`, `compute_aspect_ratio`, `infer_orientation`, `infer_needs_grading`, `extract_audio_names`; keep the video-stream guard + `infer_duration`; update the class doc comment. complexity: [low]
- [x] T0.5 Slim `lib/tasks/pito_probe.rake`: `upsert` only `{ game_id, filename, duration_seconds, updated_at }`; update comments that mention resolution/fps. complexity: [low]
- [x] T0.6 Slim `spec/factories/footages.rb`: drop the `audio_track_names`/`needs_grading` defaults and the `:needs_grading`, `:portrait`, `:with_audio_tracks` traits. complexity: [low]
- [x] T0.7 Update `spec/models/footage_spec.rb`: remove orientation-validation, `audio_track_count`, and `ORIENTATIONS` tests; keep filename presence/uniqueness + association. complexity: [low]
- [x] T0.8 Update `spec/services/pito/footage/probe_spec.rb`: drop resolution/fps/aspect_ratio/orientation/needs_grading/audio_track_names/bit_depth assertions; keep duration + success/failure cases. complexity: [low]
- [x] T0.9 Update `spec/lib/tasks/pito_probe_rake_spec.rb`: stub `Probe.call` with the slimmed Result and assert only the kept columns are upserted. complexity: [low]
- [x] T0.10 Run full `bundle exec rspec` + `bin/rubocop`; green. complexity: [low]
- [x] T0.11 Commit: `slim Footage to filename + duration; drop resolution/fps/aspect/orientation/grading/audio`. complexity: [manual]
