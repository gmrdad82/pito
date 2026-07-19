#!/usr/bin/env sh
# script/deploy-flip.sh — zero-downtime blue/green flip for the `web` deploy
# slots. Called by script/update.sh in place of a blunt `systemctl restart
# pito`; also runnable by hand (`pito deploy-flip <tag>`) for manual/debug use.
#
#   deploy-flip.sh <image-tag>     e.g. deploy-flip.sh 3.6.0  /  latest
#
# What it does, in order:
#   1. Reads PITO_ACTIVE_SLOT from .env (default: blue) → the OTHER slot is
#      idle.
#   2. Sets that idle slot's own image-tag var (PITO_TAG_BLUE / _GREEN) AND
#      the stack-wide PITO_TAG (reporting via `pito version`, but also part
#      of every slot's container environment) to the requested tag, then
#      pulls it. PITO_TAG moves BEFORE the idle slot starts on purpose: the
#      new container must boot carrying the env it will keep, so that
#      update.sh's trailing bare `docker compose up -d` computes the exact
#      config the running slot already has and leaves it alone — a config
#      drift there would RECREATE the freshly-flipped slot while the other
#      one is already stopped, i.e. the outage this script exists to
#      prevent. An aborted flip restores the previous PITO_TAG on the way
#      out.
#   3. Starts ONLY the idle slot (`docker compose up -d web-<idle>`) — the
#      active slot is never touched. Its entrypoint runs db:prepare before
#      Puma starts listening, so any pending migration lands BEFORE the new
#      slot can pass its health check; the active slot keeps serving on the
#      OLD code for however long that takes (pito's additive-migration
#      discipline is what makes this safe — see docs/architecture.md).
#   4. Polls the idle slot's own loopback probe port for /up, bounded
#      retries. Timeout → stop the idle slot and abort loudly; the active
#      slot is NEVER touched, so a failed deploy is a no-op for users.
#   5. Once healthy: stop the (old) active slot — SIGTERM, Puma drains
#      in-flight requests; ActionCable clients reconnect through `lb`
#      (unaffected throughout — it never needed reconfiguring) to the new
#      slot and re-sync, which is exactly what they're built for (see
#      app/javascript/controllers/pito/cable_health_controller.js).
#   6. Flip the bookkeeping: PITO_ACTIVE_SLOT + COMPOSE_PROFILES now point
#      at the slot that just went live (PITO_TAG already flipped in step 2).
#
# `lb` (the always-on internal load balancer in front of both slots) is
# NEVER reconfigured by any of this — its Caddyfile lists both slots with an
# active health check + lb_policy first, so it follows the handoff on its
# own next health probe. See Caddyfile.lb.

set -eu

[ -f docker-compose.yml ] || { echo "deploy-flip: run this from your pito install dir (no docker-compose.yml here)." >&2; exit 1; }

# ── Single-updater lock (shared with script/update.sh) ────────────────────────
# Same lockfile as update.sh, so a hand-run `pito deploy-flip` can never race
# a concurrent `pito update` / the autoupdate timer. When update.sh IS the
# caller it already holds the lock (we run as its child) and exports
# PITO_UPDATE_LOCK_HELD=1 — taking it again here on a fresh fd would deadlock
# against our own parent, so we skip. The fd stays open for the script's
# lifetime; the lock releases on ANY exit.
if [ "${PITO_UPDATE_LOCK_HELD:-}" != 1 ] && command -v flock >/dev/null 2>&1; then
  exec 9>".pito-update.lock"
  if ! flock -n 9; then
    echo "deploy-flip: an update/flip is already running (lock: $PWD/.pito-update.lock) — aborting." >&2
    exit 1
  fi
fi

TAG="${1:-}"
[ -n "$TAG" ] || { echo "deploy-flip: usage: deploy-flip.sh <image-tag>" >&2; exit 1; }

HEALTH_MAX_TRIES=30   # 30 * 2s = 60s bounded wait for the idle slot's /up
HEALTH_INTERVAL=2

env_get() { [ -f .env ] && sed -n "s/^$1=//p" .env | head -1 || true; }

env_set() {
  touch .env
  grep -q "^$1=" .env 2>/dev/null && { tmp=$(mktemp); grep -v "^$1=" .env > "$tmp"; mv "$tmp" .env; }
  printf '%s=%s\n' "$1" "$2" >> .env
}

# Add $1 to COMPOSE_PROFILES (comma list), dropping any token in $2
# (space-separated — the slot's mutually-exclusive sibling, "blue green"; ""
# for a plain additive token like "caddy", which is left untouched here).
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

active=$(env_get PITO_ACTIVE_SLOT); active="${active:-blue}"
case "$active" in
  blue)  idle=green; idle_port=3031 ;;
  green) idle=blue;  idle_port=3030 ;;
  *) echo "deploy-flip: PITO_ACTIVE_SLOT='$active' is not blue/green — aborting." >&2; exit 1 ;;
esac
idle_tag_var="PITO_TAG_$(printf '%s' "$idle" | tr '[:lower:]' '[:upper:]')"
prev_tag=$(env_get PITO_TAG)   # restored if the flip aborts below

echo "→ Active slot: web-$active. Deploying $TAG into idle slot web-$idle."
env_set "$idle_tag_var" "$TAG"
# PITO_TAG flips NOW, before the idle slot starts — not after the handoff.
# The new container must boot with the very env update.sh's trailing bare
# `docker compose up -d` will recompute from .env; written any later, that
# up -d would see a changed config hash and RECREATE the freshly-flipped
# slot while the old one is already stopped (a full-boot outage).
env_set PITO_TAG "$TAG"

echo "→ Pulling image for web-$idle"
docker compose pull "web-$idle"

echo "→ Starting web-$idle on the new image (entrypoint runs db:prepare before it can pass /up)"
docker compose up -d "web-$idle"

echo "→ Waiting for web-$idle to answer /up (up to $((HEALTH_MAX_TRIES * HEALTH_INTERVAL))s)…"
tries=0
until curl -fsS "http://127.0.0.1:$idle_port/up" >/dev/null 2>&1; do
  tries=$((tries + 1))
  if [ "$tries" -ge "$HEALTH_MAX_TRIES" ]; then
    echo "deploy-flip: web-$idle did not become healthy after $((HEALTH_MAX_TRIES * HEALTH_INTERVAL))s — aborting. web-$active (the active slot) was never touched." >&2
    env_set PITO_TAG "$prev_tag"   # before the stop, so an abort can't strand the new tag
    docker compose stop "web-$idle"
    exit 1
  fi
  sleep "$HEALTH_INTERVAL"
done
echo "→ web-$idle is healthy."

echo "→ Draining old slot web-$active (SIGTERM; Puma finishes in-flight requests — clients reconnect through lb to web-$idle on their own)"
docker compose stop "web-$active"

env_set PITO_ACTIVE_SLOT "$idle"
profile_set "$idle" "blue green"

echo "→ Flipped: PITO_ACTIVE_SLOT=$idle (was $active). web-$active stays stopped until its next deploy."
