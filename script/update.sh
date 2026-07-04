#!/usr/bin/env sh
# script/update.sh — update an existing pito install.
#
# Pulls the latest GHCR image and restarts — NO git pull, no rebuild. Run it
# from the install dir, or via `./pito update`.
#
# Flags:
#   --host URL         change the public base URL (else preserved)
#   --tag TAG          change the image tag (else preserved)
#   --edge             switch to / stay on edge (latest image + main CLI)
#   --version vX.Y.Z   pin to a specific release (sets image tag + CLI ref)

set -eu

HOST=""; TAG=""; REF=""; CHANNEL=""; REQ_VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host)    HOST="$2"; shift 2 ;;
    --tag)     TAG="$2";  shift 2 ;;
    --edge)    CHANNEL="edge"; shift ;;
    --version) REQ_VERSION="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "update: unknown flag '$1'" >&2; exit 1 ;;
  esac
done

[ -f docker-compose.yml ] || { echo "update: run this from your pito install dir (no docker-compose.yml here)." >&2; exit 1; }

# ── Single-updater lock ───────────────────────────────────────────────────────
# One update at a time per install dir, whoever triggers it — a manual
# `pito update`, the `pito autoupdate` timer, or a second impatient shell.
# flock(1) on a lockfile next to the compose file; the loser aborts politely
# instead of racing image pulls / compose restarts. The fd stays open for the
# script's lifetime, so the lock releases on ANY exit (success, error, kill).
if command -v flock >/dev/null 2>&1; then
  exec 9>".pito-update.lock"
  if ! flock -n 9; then
    echo "update: another update is already running (lock: $PWD/.pito-update.lock) — aborting." >&2
    exit 1
  fi
fi

env_set() {
  touch .env
  grep -q "^$1=" .env 2>/dev/null && { tmp=$(mktemp); grep -v "^$1=" .env > "$tmp"; mv "$tmp" .env; }
  printf '%s=%s\n' "$1" "$2" >> .env
}

list_tags() {
  curl -fsSL "https://api.github.com/repos/gmrdad82/pito/tags?per_page=30" 2>/dev/null \
    | grep -oE '"name": *"v[0-9][^"]*"' \
    | sed -E 's/.*"(v[0-9][^"]*)".*/\1/' \
    | sort -Vr
}

cur_tag=$(sed -n 's/^PITO_TAG=//p' .env 2>/dev/null | head -1); cur_tag="${cur_tag:-latest}"
cur_ref=$(sed -n 's/^PITO_REF=//p' .env 2>/dev/null | head -1); cur_ref="${cur_ref:-main}"

resolve_update() {
  if [ -n "${REQ_VERSION:-}" ]; then REF="$REQ_VERSION"; TAG="${REQ_VERSION#v}"; return 0; fi
  if [ "$CHANNEL" = "edge" ]; then REF="main"; TAG="latest"; return 0; fi
  # If --tag was passed (raw image tag) keep current ref, just change the image tag:
  if [ -n "$TAG" ]; then REF="$cur_ref"; return 0; fi
  # Interactive:
  tags=$(list_tags); newest=$(printf '%s\n' "$tags" | head -1)
  cur_chan=$([ "$cur_ref" = main ] && echo edge || echo "stable ($cur_ref)")
  echo "Current: $cur_chan, image tag $cur_tag." >&2
  if [ -z "$tags" ]; then echo "update: Couldn't list releases — staying on current." >&2; REF="$cur_ref"; TAG="$cur_tag"; return 0; fi
  echo "Update to:" >&2
  i=1; printf '%s\n' "$tags" | head -5 | while IFS= read -r t; do
    if [ "$t" = "$newest" ]; then printf '  %d) %s   stable (recommended)\n' "$i" "$t" >&2; else printf '  %d) %s   stable\n' "$i" "$t" >&2; fi
    i=$((i+1))
  done
  printf '  e) edge   (latest image + main CLI)\n' >&2
  printf '  s) stay   (keep %s)\n' "$cur_tag" >&2
  printf 'Pick [1]: ' >&2
  read -r pick </dev/tty || pick=""
  case "$pick" in
    e|E) REF="main"; TAG="latest" ;;
    s|S) REF="$cur_ref"; TAG="$cur_tag" ;;
    "" ) REF="$newest"; TAG="${newest#v}" ;;
    *) chosen=$(printf '%s\n' "$tags" | head -5 | sed -n "${pick}p"); [ -z "$chosen" ] && chosen="$newest"; REF="$chosen"; TAG="${chosen#v}" ;;
  esac
}

resolve_update

REPO_RAW="https://raw.githubusercontent.com/gmrdad82/pito/$REF"
echo "→ Channel: $([ "$REF" = main ] && echo edge || echo "stable ($REF)") — image tag $TAG"

echo "→ Refreshing docker-compose.yml + pito CLI"
curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO_RAW/bin/pito" -o pito && chmod +x pito

# Ensure `pito` is on PATH (best-effort) so it runs bare from anywhere. Skip the
# sudo prompt when it's already linked here.
if [ "$(readlink /usr/local/bin/pito 2>/dev/null)" != "$PWD/pito" ]; then
  sudo ln -sf "$PWD/pito" /usr/local/bin/pito 2>/dev/null \
    && echo "→ Linked /usr/local/bin/pito → $PWD/pito (run 'pito' from anywhere)" || true
fi

env_set PITO_TAG "$TAG"
env_set PITO_REF "$REF"
[ -n "$HOST" ] && env_set PITO_APP_BASE_URL "$HOST"

echo "→ Pulling the latest image"
docker compose pull

# Restart through whoever owns the stack. If a pito systemd unit exists, let it
# recreate the containers (so systemd stays the owner) instead of a bare `up -d`
# that would race the unit's `docker compose up`. The sudo prompt is expected.
echo "→ Restarting (entrypoint runs db:prepare for any new migrations)"
if command -v systemctl >/dev/null 2>&1 && systemctl cat pito.service >/dev/null 2>&1; then
  echo "  systemd service detected — restarting via 'sudo systemctl restart pito'."
  sudo systemctl restart pito
elif command -v systemctl >/dev/null 2>&1 && systemctl --user cat pito.service >/dev/null 2>&1; then
  echo "  user systemd service detected — restarting via 'systemctl --user restart pito'."
  systemctl --user restart pito
else
  docker compose up -d
fi

echo "→ Reclaiming disk (old image layers + superseded releases)"
docker image prune -f >/dev/null 2>&1 || true
# Dangling-only prune never touches TAGGED images, so superseded pito
# releases would pile up forever (G42) — drop every pito tag except the one
# this update just deployed. In-use images can't be removed (rmi fails,
# swallowed), so a running stack is never harmed.
docker images "ghcr.io/gmrdad82/pito" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null \
  | grep -v ":$TAG\$" | xargs -r docker rmi >/dev/null 2>&1 || true

echo "→ Updated."
