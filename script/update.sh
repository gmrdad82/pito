#!/usr/bin/env sh
# script/update.sh — update an existing pito install.
#
# Pulls the latest GHCR image and applies it with a zero-downtime blue/green
# flip (script/deploy-flip.sh) — NO git pull, no rebuild, and (after the
# one-time slot migration below) no restart-caused outage window either. Run
# it from the install dir, or via `./pito update`.
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
    # Pattern-anchored (not a hardcoded line range) so a new flag line can
    # never silently fall off the help again — same fix as bin/pito's usage().
    -h|--help) sed -n '2,/^#   --version/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  # Tell the child deploy-flip.sh (same lockfile) the lock is already held,
  # so it doesn't try to take it again and deadlock against its own parent.
  PITO_UPDATE_LOCK_HELD=1; export PITO_UPDATE_LOCK_HELD
fi

env_set() {
  touch .env
  grep -q "^$1=" .env 2>/dev/null && { tmp=$(mktemp); grep -v "^$1=" .env > "$tmp"; mv "$tmp" .env; }
  printf '%s=%s\n' "$1" "$2" >> .env
}

env_get() { [ -f .env ] && sed -n "s/^$1=//p" .env | head -1 || true; }

# Add $1 to COMPOSE_PROFILES (comma list), dropping any token in $2
# (space-separated — the slot's mutually-exclusive sibling, "blue green"; ""
# for a plain additive token like "caddy", left untouched here).
profile_set() {
  want="$1"; exclusive="${2:-}"
  cur=$(env_get COMPOSE_PROFILES)
  out=""
  old_ifs="$IFS"; IFS=','
  for tok in $cur; do
    [ -z "$tok" ] && continue
    skip=0
    [ "$tok" = "$want" ] && skip=1
    # Pattern match, NOT `for ex in $exclusive`: IFS is ',' inside this
    # loop, so word-splitting the space-separated list would yield ONE
    # token ("blue green") and never drop the retiring slot's profile —
    # leaving BOTH slots active after a flip.
    case " $exclusive " in *" $tok "*) skip=1 ;; esac
    [ "$skip" = 0 ] && out="${out:+$out,}$tok"
  done
  IFS="$old_ifs"
  out="${out:+$out,}$want"
  env_set COMPOSE_PROFILES "$out"
}

# Zero-downtime blue/green flip (script/deploy-flip.sh): same fetch pattern
# as docker-compose.yml/pito above — no repo checkout needed. When update.sh
# itself IS running from a repo checkout (script/ next to it), use that copy
# directly instead of a redundant fetch.
run_deploy_flip() {
  self_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  if [ -f "$self_dir/deploy-flip.sh" ]; then
    sh "$self_dir/deploy-flip.sh" "$1"
  else
    tmp=$(mktemp)
    curl -fsSL "$REPO_RAW/script/deploy-flip.sh" -o "$tmp"
    sh "$tmp" "$1"
  fi
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

echo "→ Refreshing docker-compose.yml + pito CLI + the load balancer's config"
curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO_RAW/bin/pito" -o pito && chmod +x pito
curl -fsSL "$REPO_RAW/Caddyfile.lb" -o Caddyfile.lb

# Ensure `pito` is on PATH (best-effort) so it runs bare from anywhere. Skip the
# sudo prompt when it's already linked here.
if [ "$(readlink /usr/local/bin/pito 2>/dev/null)" != "$PWD/pito" ]; then
  sudo ln -sf "$PWD/pito" /usr/local/bin/pito 2>/dev/null \
    && echo "→ Linked /usr/local/bin/pito → $PWD/pito (run 'pito' from anywhere)" || true
fi

env_set PITO_REF "$REF"
[ -n "$HOST" ] && env_set PITO_APP_BASE_URL "$HOST"

# ── One-time migration to blue/green deploy slots (3.6.0) ────────────────────
# Installs from before this feature have no PITO_ACTIVE_SLOT. Seed it —
# mirroring whatever tag was already running into PITO_TAG_BLUE, so web-blue
# comes up as a like-for-like replacement of the old single `web` service —
# and, if a direct-HTTPS ./Caddyfile exists, repoint its `reverse_proxy
# web:80` at the new internal load balancer ONCE: every update after this
# one leaves ./Caddyfile alone again (the "edit freely" promise resumes).
MIGRATING=0
if ! grep -q '^PITO_ACTIVE_SLOT=' .env 2>/dev/null; then
  MIGRATING=1
  echo "→ One-time migration to blue/green deploy slots"
  prior_tag=$(env_get PITO_TAG); prior_tag="${prior_tag:-latest}"
  env_set PITO_TAG_BLUE "$prior_tag"
  profile_set blue "blue green"
  if [ -f Caddyfile ] && grep -q 'reverse_proxy web:80' Caddyfile; then
    tmp=$(mktemp)
    sed 's/reverse_proxy web:80/reverse_proxy lb:8080/' Caddyfile > "$tmp" && mv "$tmp" Caddyfile
    echo "  → ./Caddyfile repointed at the internal load balancer (one-time; edit freely from here on)."
  fi
fi

echo "→ Pulling images"
docker compose pull

if [ "$MIGRATING" = 1 ]; then
  # The old single-`web` shape can't become web-blue/web-green/lb in place —
  # this ONE full bounce adopts the new compose shape (web-blue comes back on
  # the SAME tag it was already running, so this restart is a pure shape
  # migration, not a version change). It's the last downtime-ful restart:
  # the version this run actually asked for lands right after, via the
  # zero-downtime flip below.
  #
  # The legacy `web` container is an ORPHAN under the new compose file (no
  # `web` service any more) and still holds 127.0.0.1:3028 — the new `lb`
  # can't bind until it's gone, and neither a bare `up -d` nor the systemd
  # unit's plain `down` removes orphans. So: stop the stack the way it's
  # currently run, sweep the whole old shape away (`down --remove-orphans`;
  # containers only — volumes/data untouched), then start the new one.
  echo "→ Adopting the blue/green stack shape (this is the last downtime-ful restart)"
  if command -v systemctl >/dev/null 2>&1 && systemctl cat pito.service >/dev/null 2>&1; then
    echo "  systemd service detected — bouncing via 'sudo systemctl stop/start pito'."
    sudo systemctl stop pito
    docker compose down --remove-orphans
    sudo systemctl start pito
  elif command -v systemctl >/dev/null 2>&1 && systemctl --user cat pito.service >/dev/null 2>&1; then
    echo "  user systemd service detected — bouncing via 'systemctl --user stop/start pito'."
    systemctl --user stop pito
    docker compose down --remove-orphans
    systemctl --user start pito
  else
    docker compose down --remove-orphans
    docker compose up -d
  fi
  # Written LAST, once the new shape is actually up: PITO_ACTIVE_SLOT is the
  # migration marker (the grep above), so a failed bounce leaves it absent
  # and the next `pito update` re-runs this whole (idempotent) migration
  # instead of skipping it half-done.
  env_set PITO_ACTIVE_SLOT blue
  echo "→ Now delivering $TAG via a zero-downtime flip"
fi

run_deploy_flip "$TAG"

echo "→ Refreshing the rest of the stack (postgres, load balancer, MCP, sidecars, direct-HTTPS caddy if enabled)"
# Bare `up -d`: Compose only (re)creates services whose profile is active (or
# have none) — never the idle web slot deploy-flip just stopped, and never
# the direct-HTTPS caddy service unless its profile is actually on. Anything
# whose image/config didn't change is a no-op (no restart, no downtime) —
# INCLUDING the slot that just went live: deploy-flip wrote PITO_TAG (part of
# every slot's container env) before starting it, so the config hash computed
# here matches the running container exactly. Recreating it here would be an
# outage (the other slot is stopped) — keep that write-before-start ordering.
docker compose up -d

echo "→ Reclaiming disk (old image layers + superseded releases)"
docker image prune -f >/dev/null 2>&1 || true
# Dangling-only prune never touches TAGGED images, so superseded pito
# releases would pile up forever (G42) — drop every pito tag except the one
# this update just deployed. In-use images can't be removed (rmi fails,
# swallowed), so a running stack is never harmed.
docker images "ghcr.io/gmrdad82/pito" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null \
  | grep -v ":$TAG\$" | xargs -r docker rmi >/dev/null 2>&1 || true

echo "→ Updated."
