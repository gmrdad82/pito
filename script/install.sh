#!/usr/bin/env sh
# script/install.sh — one-shot installer for the pito Docker stack.
#
#   curl -fsSL https://raw.githubusercontent.com/gmrdad82/pito/main/script/install.sh | sh
#
# No git clone, no host Ruby — everything runs against the prebuilt GHCR image
# (ghcr.io/gmrdad82/pito). It lands a self-contained install in ./pito:
# docker-compose.yml + the pito CLI + .env + your own generated secrets.
#
# Flags:
#   --dir DIR          install location (default: ./pito)
#   --host URL         public base URL (default: prompt; e.g. https://app.pitomd.com)
#   --tag TAG          image tag to run (default: latest)
#   --service-only     skip install; only (re)configure the systemd unit
#   --cloudflared-only skip install; only print Cloudflare Tunnel guidance
#   --skip-pull        use the locally-present image (for testing a local build)
#
# Re-running is safe: existing master.key / credentials are kept.

set -eu

REPO_RAW="https://raw.githubusercontent.com/gmrdad82/pito/main"
DIR="./pito"
HOST=""
TAG="latest"
MODE="install"
SKIP_PULL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)              DIR="$2"; shift 2 ;;
    --host)             HOST="$2"; shift 2 ;;
    --tag)              TAG="$2"; shift 2 ;;
    --service-only)     MODE="service"; shift ;;
    --cloudflared-only) MODE="cloudflared"; shift ;;
    --skip-pull)        SKIP_PULL=1; shift ;;
    -h|--help)          sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install: unknown flag '$1'" >&2; exit 1 ;;
  esac
done

say()  { printf '\n\033[1;34m→ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m!  %s\033[0m\n' "$1" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

require_docker() {
  have docker || die "Docker is required. Install it: https://docs.docker.com/get-docker/"
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required (docker compose ...)."
}

# Read a value from .env (KEY=value), empty if absent.
env_get() { [ -f .env ] && sed -n "s/^$1=//p" .env | head -1 || true; }

# Set/replace KEY=value in .env (create file if needed).
env_set() {
  touch .env
  if grep -q "^$1=" .env 2>/dev/null; then
    tmp=$(mktemp); grep -v "^$1=" .env > "$tmp"; mv "$tmp" .env
  fi
  printf '%s=%s\n' "$1" "$2" >> .env
}

# ── cloudflared guidance ─────────────────────────────────────────────────────
setup_cloudflared() {
  base="${1:-$(env_get PITO_APP_BASE_URL)}"
  host=$(printf '%s' "$base" | sed -E 's#^https?://##; s#/.*$##')
  case "$base" in
    *localhost*|*127.0.0.1*|"") warn "Host is local ($base) — no tunnel needed."; return 0 ;;
  esac

  say "Cloudflare Tunnel for $host"

  if ! have cloudflared; then
    cat <<EOF
cloudflared is not installed. Install it first:
  Arch:          sudo pacman -S cloudflared
  Debian/Ubuntu: see https://pkg.cloudflare.com/  (cloudflared package)
  macOS:         brew install cloudflared
  Other:         https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/

Then re-run:  ./pito cloudflared
EOF
    return 0
  fi

  # Don't assume a fresh tunnel — show what already exists so you REUSE it
  # rather than create a duplicate (a common foot-gun if you already tunnel
  # this host to bin/dev on :3027).
  echo "Existing Cloudflare tunnels (reuse one — don't duplicate):"
  cloudflared tunnel list 2>/dev/null | sed 's/^/  /' || echo "  (none, or run 'cloudflared tunnel login' first)"

  cfg="$PWD/cloudflared-config.yml"
  if [ -e "$cfg" ]; then
    warn "$cfg exists — writing $cfg.new instead (review + merge, don't clobber)."
    cfg="$cfg.new"
  fi
  cat > "$cfg" <<EOF
# pito tunnel config — points $host at the Docker stack on 127.0.0.1:3028.
# NOTE: that's the PRODUCTION port. A dev tunnel (bin/dev) uses :3027 — keep
# them separate, or just re-point your existing tunnel's ingress to :3028.
# If you already have a tunnel, set tunnel:/credentials-file: to ITS values.
tunnel: <your-tunnel-name-or-uuid>
credentials-file: $HOME/.cloudflared/<your-tunnel-uuid>.json
ingress:
  - hostname: $host
    service: http://127.0.0.1:3028
  - service: http_status:404
EOF
  cat <<EOF
Wrote a starter config to: $cfg

• Already have a tunnel for $host? Just re-point its ingress to
  http://127.0.0.1:3028 and restart it — no new tunnel or DNS route needed.
• No tunnel yet? One time:
    cloudflared tunnel login
    cloudflared tunnel create pito        # put its name/uuid in the config above
    cloudflared tunnel route dns pito $host
    cloudflared tunnel --config "$cfg" run pito

In Cloudflare's SSL/TLS settings use mode "Full" (pito forces SSL).
EOF
}

# ── systemd unit (reboot persistence) ────────────────────────────────────────
setup_systemd() {
  say "Reboot-persistence (systemd)"
  printf 'Install a systemd unit so pito starts on boot? [u]ser / [s]ystem / [n]o: '
  read -r choice </dev/tty || choice="n"
  workdir="$PWD"
  unit_body() {
    cat <<EOF
[Unit]
Description=pito (Docker Compose)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$workdir
ExecStart=/usr/bin/env docker compose up
ExecStop=/usr/bin/env docker compose down
Restart=always
RestartSec=5

[Install]
WantedBy=$1
EOF
  }
  case "$choice" in
    u|U)
      mkdir -p "$HOME/.config/systemd/user"
      unit_body "default.target" > "$HOME/.config/systemd/user/pito.service"
      cat <<EOF
Wrote ~/.config/systemd/user/pito.service. Enable it:
  systemctl --user daemon-reload
  systemctl --user enable --now pito
  loginctl enable-linger "$USER"   # start before you log in (survives reboot)
EOF
      ;;
    s|S)
      unit_body "multi-user.target" | sudo tee /etc/systemd/system/pito.service >/dev/null
      cat <<EOF
Wrote /etc/systemd/system/pito.service. Enable it:
  sudo systemctl daemon-reload
  sudo systemctl enable --now pito
EOF
      ;;
    *) warn "Skipped systemd setup." ;;
  esac
}

# ── full install ─────────────────────────────────────────────────────────────
do_install() {
  require_docker

  say "Installing pito into $DIR"
  mkdir -p "$DIR/config"
  cd "$DIR"

  say "Fetching docker-compose.yml + the pito CLI (no git clone)"
  curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml
  curl -fsSL "$REPO_RAW/bin/pito" -o pito && chmod +x pito

  # Public host
  if [ -z "$HOST" ]; then
    printf 'Public URL pito will be reached at [http://localhost:3028]: '
    read -r HOST </dev/tty || HOST=""
    [ -z "$HOST" ] && HOST="http://localhost:3028"
  fi
  env_set PITO_APP_BASE_URL "$HOST"
  env_set PITO_TAG "$TAG"

  if [ -n "$SKIP_PULL" ]; then
    warn "Skipping image pull (--skip-pull) — using the locally-present image."
  else
    say "Pulling the image (ghcr.io/gmrdad82/pito:$TAG)"
    PITO_TAG="$TAG" docker compose pull
  fi

  bootstrap_credentials

  say "Starting the stack"
  PITO_TAG="$TAG" docker compose up -d

  say "Enrolling your login (TOTP) — scan the QR/secret below into an authenticator"
  PITO_TAG="$TAG" docker compose run --rm web bin/rails pito:tools:totp || \
    warn "TOTP enrollment failed — run './pito totp' once the stack is healthy."

  setup_cloudflared "$HOST"
  setup_systemd

  say "Done. pito is at $HOST"
  echo "Manage it from $DIR:  ./pito logs -f   ./pito console   ./pito update"
}

# Generate master.key + credentials.yml.enc with the owner's own secrets.
# Uses a one-off container with a TEMPORARY read-write ./config mount (the
# long-running compose mount is read-only). Idempotent: skips if creds exist.
bootstrap_credentials() {
  if [ -f config/credentials.yml.enc ] && [ -f config/master.key ]; then
    warn "Existing credentials kept (config/credentials.yml.enc)."
    return 0
  fi
  # A botched earlier run (or a compose :ro mount applied before the file existed)
  # can leave config/credentials.yml.enc as a DIRECTORY. Clear anything that isn't
  # a regular file so generation can write it cleanly.
  [ -e config/credentials.yml.enc ] && [ ! -f config/credentials.yml.enc ] && rm -rf config/credentials.yml.enc

  have openssl || die "openssl is required to generate secrets."

  say "Generating your secrets (master key + encrypted credentials)"
  openssl rand -hex 16 > config/master.key
  chmod 600 config/master.key

  SKB=$(openssl rand -hex 64)
  ARP=$(openssl rand -hex 32); ARD=$(openssl rand -hex 32); ARS=$(openssl rand -hex 32)
  PEPPER=$(openssl rand -hex 32)

  # Encrypt without booting Rails (just ActiveSupport). Use a plain `docker run`
  # (NOT `docker compose run`) so the compose service's read-only `:ro` mounts for
  # master.key / credentials.yml.enc are NOT applied — on a fresh install those make
  # Docker auto-create credentials.yml.enc as a read-only DIRECTORY before it exists,
  # which crashes the write (Errno::EROFS). Only the RW ./config mount is needed (no DB).
  docker run --rm \
    -v "$PWD/config:/rails/config" \
    -e SKB="$SKB" -e ARP="$ARP" -e ARD="$ARD" -e ARS="$ARS" -e PEPPER="$PEPPER" \
    "ghcr.io/gmrdad82/pito:$TAG" bundle exec ruby -e '
      require "active_support"
      require "active_support/encrypted_configuration"
      yaml = <<~YAML
        secret_key_base: #{ENV["SKB"]}
        active_record_encryption:
          primary_key: #{ENV["ARP"]}
          deterministic_key: #{ENV["ARD"]}
          key_derivation_salt: #{ENV["ARS"]}
        tokens:
          pepper: #{ENV["PEPPER"]}
        postgres:
          production:
            database: pito_production
            username: pito
            password: ""
      YAML
      ActiveSupport::EncryptedConfiguration.new(
        config_path: "config/credentials.yml.enc",
        key_path: "config/master.key",
        env_key: "RAILS_MASTER_KEY",
        raise_if_missing_key: true
      ).write(yaml)
      puts "credentials written"
    '
}

case "$MODE" in
  install)     do_install ;;
  service)     setup_systemd ;;
  cloudflared) setup_cloudflared ;;
esac
