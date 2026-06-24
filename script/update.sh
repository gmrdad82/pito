#!/usr/bin/env sh
# script/update.sh — update an existing pito install.
#
# Pulls the latest GHCR image and restarts — NO git pull, no rebuild. Run it
# from the install dir, or via `./pito update`.
#
# Flags:
#   --host URL   change the public base URL (else preserved)
#   --tag TAG    change the image tag (else preserved; default latest)

set -eu

REPO_RAW="https://raw.githubusercontent.com/gmrdad82/pito/main"
HOST=""; TAG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --tag)  TAG="$2";  shift 2 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "update: unknown flag '$1'" >&2; exit 1 ;;
  esac
done

[ -f docker-compose.yml ] || { echo "update: run this from your pito install dir (no docker-compose.yml here)." >&2; exit 1; }

env_set() {
  touch .env
  grep -q "^$1=" .env 2>/dev/null && { tmp=$(mktemp); grep -v "^$1=" .env > "$tmp"; mv "$tmp" .env; }
  printf '%s=%s\n' "$1" "$2" >> .env
}

echo "→ Refreshing docker-compose.yml + pito CLI"
curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO_RAW/bin/pito" -o pito && chmod +x pito

[ -n "$HOST" ] && env_set PITO_APP_BASE_URL "$HOST"
[ -n "$TAG" ]  && env_set PITO_TAG "$TAG"

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

echo "→ Reclaiming disk (old image layers)"
docker image prune -f >/dev/null 2>&1 || true

echo "→ Updated."
