# `list videos`: move channel + visibility to `with`; rename Privacy → Visibility; add `scheduled` filter

> Status: Ready — execute on branch `followup-smart-link` (PR #68).

## Sign-off

- [x] Drafted — 2026-06-10
- [x] Audited — 2026-06-10 (approved by user in chat)

## North star

`list videos` defaults to just `# / Title`. `channel` and `visibility` become optional
`with` columns (`list videos with channel, visibility`). The label formerly "Privacy"
reads **"Visibility"** (from Pito::Copy). The visibility/state **filters** are
`published` / `unlisted` / `scheduled` (three), and they compose with `with` columns
(e.g. `list videos scheduled with channel, visibility`).

## Locked decisions

| Topic            | Decision                                                                                |
| ---------------- | --------------------------------------------------------------------------------------- |
| Default columns  | `# / Title` only. `channel` + `visibility` are `with`-columns.                          |
| Visibility label | "Visibility" via new `pito.copy.videos.columns.visibility`.                             |
| `privacy` token  | DROPPED (no alias). Canonical is `visibility`; cell value is the privacy_status label.  |
| Filters          | `published` / `unlisted` / `scheduled` — three; compose with `with` columns.            |
| `scheduled`      | `Video.scheduled` = `where("publish_at > ?", Time.current)` (future scheduled publish). |
| Branch           | `followup-smart-link` (PR #68), per user.                                               |

## Complexity hints

| Hint       | Meaning                                           |
| ---------- | ------------------------------------------------- |
| `[low]`    | mechanical / single-file / pattern-following edit |
| `[manual]` | operator: verification runs, commits              |

## Phase index

- P0 — Columns, copy, filters
- P1 — Specs

## P0 — Columns, copy, filters

- [x] T0.1 Add `pito.copy.videos.columns.visibility: "Visibility"` to `config/locales/pito/copy/en.yml`. complexity: [low]
- [x] T0.2 Add `:channel` + `:visibility` columns to `Video::ListColumns::COLUMNS` (values: `v.channel.at_handle`; the privacy_status label), with the visibility heading sourced from the new copy key. complexity: [low]
- [x] T0.3 Set `channel` + `visibility` `requires_with: true` and rename the `privacy` sort token to `visibility` (drop the `privacy` alias) in `Video::ListColumns` `SORT_SPECS`/`SORT_VOCAB`. complexity: [low]
- [x] T0.4 Trim `Video::ListColumns.base_sort_tokens` to `%w[id title]`. complexity: [low]
- [x] T0.5 Remove `Channel`/`Privacy` from the default `table_heading` + default cells in `app/services/pito/message_builder/video/list.rb` (default = `# / Title` + extra columns). complexity: [low]
- [x] T0.6 Add a `scheduled` scope to `app/models/video.rb`: `scope :scheduled, -> { where("publish_at > ?", Time.current) }`. complexity: [low]
- [x] T0.7 Add `"scheduled"` to the list handler's visibility-filter map and rename `PRIVACY_FILTERS`→`VISIBILITY_FILTERS` / `privacy_filter_from`→`visibility_filter_from` in `app/services/pito/chat/handlers/list.rb`. complexity: [low]
- [x] T0.8 Update `list videos --help` columns + the `list-videos` hashtag sort-by help copy to include `channel` + `visibility` (and document the three filters) in `en.yml`. complexity: [low]
- [x] T0.9 Commit: `list videos: channel+visibility with-columns; Privacy→Visibility; add scheduled filter`. complexity: [manual]

## P1 — Specs

- [x] T1.1 Update `spec/services/pito/message_builder/video/list_spec.rb` — default = `# / Title`; `with channel, visibility` shows them with the "Visibility" heading. complexity: [low]
- [x] T1.2 Update `spec/services/pito/message_builder/video/list_columns_spec.rb` — `channel`/`visibility` columns; `requires_with` sort; `privacy` token gone. complexity: [low]
- [x] T1.3 Update the `list` handler spec — `scheduled` filter scopes correctly and composes with `with` columns. complexity: [low]
- [x] T1.4 Add a `Video` model spec for the `scheduled` scope. complexity: [low]
- [x] T1.5 Update engine ghost + `list-videos` hashtag-help specs — `channel` + `visibility` offered. complexity: [low]
- [x] T1.6 Run full `bundle exec rspec` + `bin/rubocop`; confirm green. complexity: [manual]
- [x] T1.7 Commit: `specs: list videos channel/visibility with-columns + scheduled filter`. complexity: [manual]
