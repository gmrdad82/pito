#!/usr/bin/env sh
# capture.sh — regenerates the pito-cli terminal casts (install / manage /
# update) via VHS. SAFE to run any time: this never touches a real Docker
# daemon, the real network, or the real system. See "Safety model" below for
# exactly how each guard works, and README.md for the human-readable version.
#
# Usage:
#   bash capture.sh                      # casts REPO=~/Dev/pito (default)
#   REPO=/path/to/pito bash capture.sh   # cast a different checkout
#   CAPTURE_ONLY="install" bash capture.sh   # just one cast (smoke-testing
#                                             # the rig itself, faster
#                                             # iteration); space-separated
#                                             # subset of: install cli update
#
# Output: out/pito-install-cast.{gif,txt}, out/pito-cli-cast.{gif,txt},
# out/pito-update-cast.{gif,txt} — next to this script.

set -eu

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO="${REPO:-$HOME/Dev/pito}"
OUT="$HERE/out"

[ -f "$REPO/script/install.sh" ] || {
  echo "capture.sh: '$REPO' doesn't look like a pito checkout (no script/install.sh)." >&2
  echo "            Point REPO at one: REPO=/path/to/pito bash capture.sh" >&2
  exit 1
}
command -v vhs >/dev/null 2>&1 || {
  echo "capture.sh: vhs is required (https://github.com/charmbracelet/vhs) and must be on PATH." >&2
  exit 1
}

# ── Fresh sandbox, casts the CURRENT repo state ─────────────────────────────
# Every run stages a read-only copy of the 6 files the installer/CLI actually
# fetch/run (never written back to $REPO) into a throwaway mktemp dir, mirroring
# the real repo's bin/ and script/ layout so fakebin/curl's path matching works
# unmodified. This means the cast always reflects whatever's on disk in $REPO
# right now — no stale content baked into a committed fixture.
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/pito-capture.XXXXXX")
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT INT TERM

mkdir -p "$SANDBOX/src/bin" "$SANDBOX/src/script"
cp "$REPO/script/install.sh"     "$SANDBOX/src/script/install.sh"
cp "$REPO/script/update.sh"      "$SANDBOX/src/script/update.sh"
cp "$REPO/script/deploy-flip.sh" "$SANDBOX/src/script/deploy-flip.sh"
cp "$REPO/bin/pito-cli"          "$SANDBOX/src/bin/pito-cli"
cp "$REPO/bin/pito"              "$SANDBOX/src/bin/pito"
cp "$REPO/docker-compose.yml"    "$SANDBOX/src/docker-compose.yml"
cp "$REPO/Caddyfile.lb"          "$SANDBOX/src/Caddyfile.lb"

# The install cast runs this copy directly (`./install.sh --dir ./pito-cli`);
# it then fetches the rest of the file list above back out through fakebin/curl.
cp "$SANDBOX/src/script/install.sh" "$SANDBOX/install.sh"
chmod +x "$SANDBOX/install.sh"

# ── Safety model (four independent guards, all active on every run) ────────
#   1. fakebin/docker never execs a real docker — a pure case-statement no-op
#      that pattern-matches the handful of `docker`/`docker compose` shapes
#      the installer/CLI use and prints realistic-looking output.
#   2. DOCKER_HOST=tcp://127.0.0.1:1 — a second, independent guard: even if
#      something slipped past the PATH shadowing, this host refuses the
#      connection instantly (nothing is listening there).
#   3. fakebin/curl never touches the network. It serves the 6 files staged
#      above from $PITO_SRC (this run's sandbox copy — see above) for
#      matching raw.githubusercontent.com paths, answers the GitHub releases
#      API with 5 canned version tags, answers deploy-flip's localhost /up
#      health probe as instantly healthy, and silently no-ops every other URL.
#   4. fakebin/sudo and fakebin/readlink are no-op successes: sudo exits 0
#      without ever exec'ing its argv (so `sudo ln -sf ... /usr/local/bin/
#      pito-cli` "succeeds" in the installer's eyes — no real symlink is ever
#      created); readlink answers the two /usr/local/bin probes as if that
#      (nonexistent) symlink already points at this sandbox, so
#      `pito-cli update`'s re-link check is silently satisfied instead of
#      leaking this sandbox's tmp path into the transcript. Neither ever
#      touches the real filesystem outside this sandbox.
#   5. Everything above lives inside $SANDBOX, deleted (`trap ... EXIT`) the
#      moment this script exits — success, failure, or interrupt.
#
# No systemd unit, no Cloudflare tunnel, no real credentials, no real backup
# timer, no real PATH symlink, no real image pull — ever.
export PATH="$HERE/fakebin:$PATH"
export DOCKER_HOST="tcp://127.0.0.1:1"
export PITO_SRC="$SANDBOX/src"   # fakebin/curl serves repo files from here
export CAST_DIR="$SANDBOX"       # the 3 tapes are parameterized on this (no hardcoded paths)

# crop_to_content GIF — best-effort: the tapes record at a fixed 2000px
# canvas height (the workaround for a vhs/xterm.js rendering stall that
# reproduced when the terminal scrolled — see the tapes' SAFETY comment), so
# every raw render has a lot of blank space below the last line. If
# ImageMagick's `magick` is on PATH, tighten the GIF to its actual content
# height (top-anchored, +40px margin) for a well-framed final GIF; the
# animation (frame count/timing/loop) is untouched, only the canvas shrinks.
# Purely cosmetic — skipped with a notice if `magick` isn't installed.
crop_to_content() {
  gif="$1"
  command -v magick >/dev/null 2>&1 || {
    echo "   (magick not found — skipping crop; $gif stays at the full 2000px canvas)" >&2
    return 0
  }
  frames_dir=$(mktemp -d "$SANDBOX/crop.XXXXXX")
  magick "$gif" -coalesce "$frames_dir/f-%04d.png"
  last=$(ls "$frames_dir"/f-*.png | tail -1)
  bg=$(magick "$last" -format '%[pixel:p{0,1999}]' info:)
  trimmed=$(magick "$last" -bordercolor "$bg" -border 1 -fuzz 2% -trim -format '%h' info:)
  case "$trimmed" in ''|*[!0-9]*) return 0 ;; esac   # couldn't measure — leave as-is
  h=$((trimmed + 40))
  magick "$gif" -coalesce -gravity North -crop "1200x${h}+0+0" +repage -loop 0 -layers Optimize "$gif.tmp"
  mv "$gif.tmp" "$gif"
}

mkdir -p "$OUT"
cd "$HERE"   # tapes' `Output out/...` is relative to here

# Space-separated subset of {install cli update} to render; default is all
# three. See CAPTURE_ONLY in the usage comment above.
ONLY="${CAPTURE_ONLY:-install cli update}"

case " $ONLY " in *" install "*)
  echo "==> pito-install-cast — installs into \$CAST_DIR/pito-cli"
  vhs pito-install-cast.tape
  crop_to_content "$OUT/pito-install-cast.gif"
  ;;
esac

case " $ONLY " in *" cli "*)
  echo "==> pito-cli-cast — bare 'pito-cli' subcommands"
  vhs pito-cli-cast.tape
  crop_to_content "$OUT/pito-cli-cast.gif"
  ;;
esac

case " $ONLY " in *" update "*)
  echo "==> pito-update-cast — bare 'pito-cli update' (blue/green flip)"
  vhs pito-update-cast.tape
  crop_to_content "$OUT/pito-update-cast.gif"
  ;;
esac

echo "==> Done. GIFs + txt transcripts in $OUT/"
