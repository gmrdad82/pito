# Footage

> How Pito tracks recorded-but-unpublished footage per game.

Footage in Pito is a single **manual total per game**: how many hours of raw
recordings you have for that game, in whole and half hours. There is no per-file
model, no automatic ingest, and no `ffprobe` integration baked into Rails — you
own the number, and Pito just stores and displays it.

## Data model

Footage lives in one column on `games`:

| Column          | Type                       | Meaning                                                  |
| --------------- | -------------------------- | -------------------------------------------------------- |
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
- **`#<handle> footage <hours>`** — the follow-up form. After Pito shows you a
  game (so the reply handle is live), reply with `footage <hours>` and the
  follow-up engine delegates to the same `footage` verb handler scoped to that
  game.

Negative or non-numeric hours are rejected with a usage hint. Bare `footage` or
an unknown subcommand also returns the usage hint naming both forms.

Handler: `Pito::Chat::Handlers::Footage` (`self.verb = :footage`), with
subcommands `update` and `snippet`.

## `footage snippet` — the ffprobe one-liner

`footage snippet` renders a copyable shell one-liner (no rake task, no Rails
involvement). You run it **inside your footage folder**; it sums the durations
of every file there and prints the total in hours, which you then paste into
`footage update <id> <hours>`.

What the one-liner does:

1. `find . -maxdepth 1 -type f` — every file in the current folder (non-recursive).
2. `ffprobe -v error -show_entries format=duration` — reads each file's duration
   in seconds.
3. `awk '{s+=int(($1+1799)/1800)} END{printf "%.1f", s/2}'` — ceils **each
   file** up to the next half-hour (1800 s) and sums, then prints the 1-decimal
   total in hours.
4. `wl-copy` (when available) — copies the total to the Wayland clipboard.

The exact command is `Pito::Footage::SnippetComponent::COMMAND`. `ffprobe`
(shipped with FFmpeg) must be installed on the machine where you run it:

```bash
# Arch / EndeavourOS
sudo pacman -S ffmpeg
# macOS
brew install ffmpeg
# Ubuntu / Debian
sudo apt-get install ffmpeg
```

## UI component

`Pito::Footage::SnippetComponent` renders the copyable one-liner as a `:system`
event. The payload is built by `Pito::MessageBuilder::Footage::Snippet`. The
component is wired to the shared `pito--clipboard` Stimulus controller: clicking
the copy affordance writes the command to the clipboard and flips the feedback
label to "Copied!". Its copy/aria/hint strings come from
`config/locales/.../pito.footage.snippet.*`.
