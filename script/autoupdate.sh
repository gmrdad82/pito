#!/usr/bin/env sh
# script/autoupdate.sh — keep a pito install on the newest release, unattended.
#
#   pito autoupdate              check once; update + notify if newer
#   pito autoupdate --check      dry-run: report what would happen, change nothing
#   pito autoupdate --install    install the systemd timer (15 min) + logrotate
#   pito autoupdate --uninstall  remove the timer (log + logrotate rule kept)
#
# The PULL model: the server checks GitHub for a newer release tag every
# 15 minutes and applies it with the same `pito update` you would run by
# hand — so CI needs NO deploy secrets, no SSH from runners, nothing.
# Concurrency is safe by construction: `pito update` itself holds the
# single-updater flock, so a manual update and the timer can never race.
#
# Update fires ONLY when the release's multi-arch image manifest is already
# live on GHCR — a tag alone isn't enough (`pito update` rewrites .env before
# pulling, so firing mid-build would strand the install on a missing tag).
#
# Log: ./log/autoupdate.log in the install dir (rotated weekly by the
# logrotate rule --install writes). Slack: set SLACK_WEBHOOK in .env to get a
# curl notification when an update runs (success or failure); unset = silent.
#
# Channel: stable only. Installs on the edge channel (PITO_REF=main) are
# skipped — edge deliberately tracks `latest` by hand.

set -eu

REPO="gmrdad82/pito"
MODE="run"

case "${1:-}" in
  --check)     MODE="check" ;;
  --install)   MODE="install" ;;
  --uninstall) MODE="uninstall" ;;
  -h|--help)   awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
  "") ;;
  *) echo "autoupdate: unknown flag '$1'" >&2; exit 1 ;;
esac

[ -f docker-compose.yml ] || { echo "autoupdate: run from your pito install dir (no docker-compose.yml here)." >&2; exit 1; }

LOG_DIR="$PWD/log"
LOG_FILE="$LOG_DIR/autoupdate.log"

env_get() { [ -f .env ] && sed -n "s/^$1=//p" .env | head -1 || true; }

log() {
  mkdir -p "$LOG_DIR"
  printf '[%s] %s\n' "$(date -Iseconds)" "$1" | tee -a "$LOG_FILE"
}

# Slack via plain curl — mirrors the CI notifier's payload shape. Best-effort:
# a webhook hiccup must never fail the update path.
notify() {
  webhook="$(env_get SLACK_WEBHOOK)"
  [ -n "$webhook" ] || return 0
  payload=$(printf '{"text":"%s"}' "$1")
  curl -fsS -X POST -H 'Content-type: application/json' -d "$payload" "$webhook" >/dev/null 2>&1 || \
    log "slack notification failed (continuing)"
}

newest_release() {
  curl -fsSL "https://api.github.com/repos/$REPO/tags?per_page=30" 2>/dev/null \
    | grep -oE '"name": *"v[0-9][^"]*"' \
    | sed -E 's/.*"(v[0-9][^"]*)".*/\1/' \
    | sort -Vr | head -1
}

# True when GHCR already serves the multi-arch manifest for $1 (bare semver).
image_published() {
  ver="$1"
  tok=$(curl -fsSL "https://ghcr.io/token?scope=repository:$REPO:pull" 2>/dev/null \
    | sed -n 's/.*"token": *"\([^"]*\)".*/\1/p')
  [ -n "$tok" ] || return 1
  curl -fsSI -o /dev/null \
    -H "Authorization: Bearer $tok" \
    -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://ghcr.io/v2/$REPO/manifests/$ver" >/dev/null 2>&1
}

run_check() {
  ref="$(env_get PITO_REF)"; ref="${ref:-main}"
  if [ "$ref" = "main" ]; then
    log "edge channel (PITO_REF=main) — autoupdate only serves stable installs; skipping."
    return 0
  fi

  cur="$(env_get PITO_TAG)"; cur="${cur:-latest}"
  newest="$(newest_release)"
  if [ -z "$newest" ]; then
    log "could not list releases (offline / API limit) — will retry next run."
    return 0
  fi

  if [ "v$cur" = "$newest" ] || [ "$(printf '%s\nv%s\n' "$newest" "$cur" | sort -V | tail -1)" = "v$cur" ]; then
    [ "$MODE" = "check" ] && log "up to date (current v$cur, newest $newest)."
    return 0
  fi

  if ! image_published "${newest#v}"; then
    log "release $newest is tagged but its image is not on GHCR yet — waiting for the next run."
    return 0
  fi

  if [ "$MODE" = "check" ]; then
    log "would update: v$cur -> $newest (image is live on GHCR)."
    return 0
  fi

  log "updating v$cur -> $newest…"
  if ./pito update --version "$newest" >>"$LOG_FILE" 2>&1; then
    log "updated to $newest."
    notify ":rocket: pito auto-updated to \`$newest\` on $(hostname)"
  else
    log "UPDATE FAILED for $newest — see $LOG_FILE."
    notify ":rotating_light: pito auto-update to \`$newest\` FAILED on $(hostname) — check $LOG_FILE"
    return 1
  fi
}

install_timer() {
  command -v systemctl >/dev/null 2>&1 || { echo "autoupdate --install needs systemd." >&2; exit 1; }
  workdir="$PWD"
  user="$(id -un)"

  echo "Installing pito-autoupdate.timer (every 15 min) + logrotate rule (sudo needed)…"
  sudo tee /etc/systemd/system/pito-autoupdate.service >/dev/null <<EOF
[Unit]
Description=pito auto-update (pull newest release from GHCR)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
User=$user
WorkingDirectory=$workdir
ExecStart=$workdir/pito autoupdate
EOF
  sudo tee /etc/systemd/system/pito-autoupdate.timer >/dev/null <<EOF
[Unit]
Description=pito auto-update check, every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
  sudo tee /etc/logrotate.d/pito-autoupdate >/dev/null <<EOF
$workdir/log/autoupdate.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    copytruncate
}
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now pito-autoupdate.timer
  echo "pito-autoupdate.timer enabled — checks every 15 min; log: $workdir/log/autoupdate.log"
  echo "Optional: set SLACK_WEBHOOK=<url> in $workdir/.env for update notifications."
}

uninstall_timer() {
  command -v systemctl >/dev/null 2>&1 || { echo "autoupdate --uninstall needs systemd." >&2; exit 1; }
  sudo systemctl disable --now pito-autoupdate.timer 2>/dev/null || true
  sudo rm -f /etc/systemd/system/pito-autoupdate.timer /etc/systemd/system/pito-autoupdate.service
  sudo systemctl daemon-reload
  echo "pito-autoupdate.timer removed (log + logrotate rule kept)."
}

case "$MODE" in
  run|check)  run_check ;;
  install)    install_timer ;;
  uninstall)  uninstall_timer ;;
esac
