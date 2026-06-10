# Footage `--force`: re-probe & overwrite already-imported footage

> Status: in progress — branch `followup-smart-link` (PR #68).

## Sign-off

- [x] Drafted
- [x] Audited — approved by user in chat ("Unify the chat verb and hashtag verb to send --force, and update the Rake task to accept --force").

## North star

A `--force` flag flows end-to-end so re-importing footage with unchanged
filenames (e.g. after re-encoding 1440p → 1080p) re-probes and overwrites the
existing `Footage` rows instead of skipping them. The user types `--force` in
both the `footage` chat verb and the `#<handle> footage` hashtag follow-up; the
generated snippet emits `-- --force`; the rake task reads `--force` from `ARGV`.

## Locked decisions

| Topic             | Decision                                                                                             |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| Flag spelling     | `--force` everywhere the user types it (chat verb + hashtag follow-up).                              |
| Snippet form      | `bin/rails pito:tools:probe game=N path="…/*" -- --force` — the `--` lets rake pass `--force` on.    |
| Rake detection    | `force = ARGV.include?("--force") \|\| ENV["force"].to_s == "1"` (keeps the `force=1` path working). |
| Verb placement    | `footage game <id> [--force] <path>` — flag before the path, or trailing; never inside the path.     |
| Behavior on force | Re-run ffprobe and `upsert` every matched file (already implemented in the task body).               |
| Branch            | `followup-smart-link` (PR #68). Do NOT merge — hold for the user's manual validation.                |

## Phase index

- P0 — Wire `--force` end-to-end (rake → component → builder → chat verb → follow-up → copy) + specs.

## P0 — Force flag end-to-end

- [x] T0.1 Update `lib/tasks/pito_probe.rake`: set `force` from `ARGV.include?("--force") || ENV["force"].to_s == "1"`; update the doc comment + usage `desc` to show `-- --force`. complexity: [low]
- [x] T0.2 `app/components/pito/footage/probe_command_component.rb`: add a `force:` kwarg (default `false`); append ` -- --force` to `command_text` when set. complexity: [low]
- [x] T0.3 `app/services/pito/message_builder/game/footage_import.rb`: add a `force:` kwarg (default `false`); pass it to `ProbeCommandComponent`. complexity: [low]
- [x] T0.4 `app/services/pito/chat/handlers/footage.rb`: parse a `--force` (or bare `force`) flag out of the args in `parse_args`; pass `force:` to `FootageImport.call`. complexity: [low]
- [x] T0.5 `app/services/pito/follow_up/handlers/game_detail.rb`: in `handle_footage`, parse `--force` out of the args tail; pass `force:` to `FootageImport.call`. complexity: [low]
- [x] T0.6 Copy: update the two `footage` `--help` `usage:` strings to `footage game <id> [--force] <path>` and add a `"--force"` Option description, in `config/locales/pito/copy/en.yml`. complexity: [low]
- [x] T0.7 Update `spec/components/pito/footage/probe_command_component_spec.rb`: `command_text` appends `-- --force` when `force: true`; unchanged when omitted. complexity: [low]
- [x] T0.8 Update `spec/services/pito/message_builder/game/footage_import_spec.rb`: `force: true` produces a snippet containing `-- --force`. complexity: [low]
- [x] T0.9 Update `spec/services/pito/chat/handlers/footage_spec.rb`: `footage game <id> --force <path>` (and trailing form) sets force; snippet contains `-- --force`; no flag → no `--force`. complexity: [low]
- [x] T0.10 Update `spec/services/pito/follow_up/handlers/game_detail_spec.rb`: `#<handle> footage --force <path>` produces a snippet containing `-- --force`. complexity: [low]
- [x] T0.11 Update `spec/lib/tasks/pito_probe_rake_spec.rb`: invoking with `--force` in `ARGV` re-probes/overwrites an already-imported file. complexity: [low]
- [x] T0.12 Run full `bundle exec rspec` + `bin/rubocop`; green. complexity: [low]
- [x] T0.13 Commit: `footage: --force flag to re-probe & overwrite already-imported footage`. complexity: [manual]
