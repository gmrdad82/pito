# Footage

> How PITO tracks recorded-but-unpublished footage per game.

Footage in PITO is a single **manual total per game**: how many hours of raw
recordings you have for that game, in whole and half hours. There is no per-file
model, no automatic ingest, and no `ffprobe` integration baked into Rails — you
own the number, and PITO just stores and displays it.

## Data model

Footage lives in one column on `games`:

| Column          | Type                                         | Meaning                                               |
| --------------- | -------------------------------------------- | ----------------------------------------------------- |
| `footage_hours` | `decimal(6,1)`, default `0.0`, `null: false` | Total recorded hours for the game, in 0.5-hour steps. |

That's it. No `Footage` model, no `[game_id, filename]` rows. The value is a
running total you maintain by hand as you record more.

## Setting footage from the chatbox

Two surfaces write `footage_hours`:

- **`footage update <id> <hours>`** — the full form. `<id>` is a numeric game ID
  (`123` or `#123`); a non-numeric or unknown reference returns a witty
  not-found. `<hours>` is parsed with `BigDecimal` (exact, never `Float`) and
  **rounded up to the next 0.5**, so any positive value lands on a clean
  half-hour step. The success event confirms the new total (e.g. `12.5h`).
- **`#<handle> footage <hours>`** — the follow-up form. After PITO shows you a
  game (so the reply handle is live), reply with `footage <hours>` and the
  follow-up engine delegates to the same `footage` verb handler scoped to that
  game.

Negative or non-numeric hours are rejected with a usage hint. Bare `footage` or
an unknown subcommand also returns the usage hint naming the surviving form.

Handler: `Pito::Chat::Handlers::Footage` (`self.verb = :footage`), with the
single subcommand `update`.

## Measuring footage — pito-tui

PITO itself has no `ffprobe` integration and never did more than store the
number. The `footage snippet` shell one-liner that used to render inline in
the chatbox was removed (2026-07-13) — probing your recordings only makes
sense on the machine where the files (and `ffprobe`) actually live, so that
flow now lives in **pito-tui** (ctrl+f): pick a game, browse local folders,
select the files to probe, and it writes the total straight through this same
`footage update <id> <hours>` tool. See the pito-tui docs for the ffprobe
requirement and the folder-navigator UI.
