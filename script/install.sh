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
# Re-running is safe and non-destructive: existing master.key / credentials are
# kept, the Postgres volume (channels, videos, games, /config API keys + webhooks)
# is never touched, and TOTP is NOT re-enrolled — your authenticator keeps working.
# To just update the image use `./pito update`; to (re)configure the service or
# tunnel use `./pito service` / `./pito cloudflared`.

set -eu

REPO_RAW="https://raw.githubusercontent.com/gmrdad82/pito/main"
DIR="./pito"
HOST=""
TAG="latest"
MODE="install"
SKIP_PULL=""
CREDS_FRESH=0   # set to 1 by bootstrap_credentials only when it mints NEW secrets

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

# ── cloudflared tunnel (auto-configured + run as a service) ───────────────────
# Writes the ingress config to cloudflared's OWN dir (~/.cloudflared/config.yml),
# reuses an existing tunnel when one is configured (running a tunnel needs only its
# creds JSON, never a fresh account login), otherwise creates one, and installs a
# systemd service so the tunnel comes up on boot — no manual `cloudflared tunnel run`.
setup_cloudflared() {
  base="${1:-$(env_get PITO_APP_BASE_URL)}"
  host=$(printf '%s' "$base" | sed -E 's#^https?://##; s#/.*$##')
  case "$base" in
    *localhost*|*127.0.0.1*|"") warn "Host is local ($base) — no tunnel needed."; return 0 ;;
  esac

  say "Cloudflare Tunnel for $host"

  if ! have cloudflared; then
    cat <<EOF
cloudflared is not installed — install it, then re-run  ./pito cloudflared :
  Arch:          sudo pacman -S cloudflared
  Debian/Ubuntu: https://pkg.cloudflare.com/  (cloudflared package)
  macOS:         brew install cloudflared
  Other:         https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
EOF
    return 0
  fi

  cfdir="$HOME/.cloudflared"
  cfg="$cfdir/config.yml"
  mkdir -p "$cfdir"

  if [ -f "$cfg" ] && grep -q '^tunnel:' "$cfg" && grep -q 3028 "$cfg"; then
    # A working tunnel→:3028 config already exists — REUSE it untouched. This is
    # also the path when the account cert has expired: running needs only the
    # creds JSON, so we never call account-level ops (list/create/route) here.
    say "Reusing existing tunnel config ($cfg)"
  elif [ -f "$cfg" ] && grep -q '^tunnel:' "$cfg"; then
    # Tunnel exists but its ingress doesn't point at the prod port — fix in place.
    say "Repointing existing tunnel ingress → http://127.0.0.1:3028"
    tunnel_id=$(sed -n 's/^tunnel:[[:space:]]*//p' "$cfg" | head -1)
    creds=$(sed -n 's/^credentials-file:[[:space:]]*//p' "$cfg" | head -1)
    [ -z "$creds" ] && creds="$cfdir/$tunnel_id.json"
    cp "$cfg" "$cfg.bak.$$" && warn "Backed up $cfg → $cfg.bak.$$"
    write_cf_config "$cfg" "$tunnel_id" "$creds" "$host"
  else
    # No tunnel yet — create one. Account login is a one-time browser step.
    if [ ! -f "$cfdir/cert.pem" ]; then
      say "Logging in to Cloudflare (opens a browser — pick the zone for $host)"
      cloudflared tunnel login </dev/tty || { warn "cloudflared login failed — re-run ./pito cloudflared"; return 0; }
    fi
    tunnel_name="${PITO_TUNNEL:-pito}"
    say "Creating tunnel '$tunnel_name'"
    create_out=$(cloudflared tunnel create "$tunnel_name" 2>&1) || {
      printf '%s\n' "$create_out" >&2
      warn "tunnel create failed — re-run ./pito cloudflared after 'cloudflared tunnel login'."
      return 0
    }
    printf '%s\n' "$create_out"
    tunnel_id=$(printf '%s' "$create_out" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
    [ -z "$tunnel_id" ] && tunnel_id="$tunnel_name"
    write_cf_config "$cfg" "$tunnel_id" "$cfdir/$tunnel_id.json" "$host"
    say "Routing DNS: $host → tunnel"
    cloudflared tunnel route dns "$tunnel_name" "$host" 2>&1 | sed 's/^/  /' || \
      warn "route dns failed (may already exist) — otherwise add a CNAME for $host in Cloudflare."
  fi

  install_cloudflared_service "$cfg"

  cat <<EOF

Tunnel for $host is configured and runs on boot (systemd unit: cloudflared).
In Cloudflare's SSL/TLS settings use mode "Full" (pito forces SSL).
EOF
}

# Write a cloudflared ingress config:  write_cf_config PATH TUNNEL_ID CREDS_FILE HOST
write_cf_config() {
  cat > "$1" <<EOF
# pito tunnel — routes $4 to the Docker stack on 127.0.0.1:3028 (the PRODUCTION
# port; a dev tunnel for bin/dev would use :3027). Managed by pito's installer.
tunnel: $2
credentials-file: $3
ingress:
  - hostname: $4
    service: http://127.0.0.1:3028
  - service: http_status:404
EOF
}

# Run cloudflared as a reboot-persistent systemd service:  install_cloudflared_service CONFIG
install_cloudflared_service() {
  cfg="$1"
  bin=$(command -v cloudflared)
  say "Installing cloudflared as a systemd service (tunnel runs on boot — no manual run)"
  sudo tee /etc/systemd/system/cloudflared.service >/dev/null <<EOF
[Unit]
Description=cloudflared tunnel (pito)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$bin tunnel --no-autoupdate --config $cfg run
Restart=always
RestartSec=5
User=$(id -un)

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now cloudflared
  say "cloudflared.service enabled + started."
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
      systemctl --user daemon-reload
      systemctl --user enable --now pito
      loginctl enable-linger "$(id -un)" 2>/dev/null || \
        warn "Could not enable linger — run: loginctl enable-linger $(id -un)  (so it starts before login)"
      say "pito.service (user) enabled + started."
      ;;
    s|S)
      unit_body "multi-user.target" | sudo tee /etc/systemd/system/pito.service >/dev/null
      sudo systemctl daemon-reload
      sudo systemctl enable --now pito
      say "pito.service (system) enabled + started."
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

  if [ "$CREDS_FRESH" = "1" ]; then
    say "Enrolling your login (TOTP) — scan the QR/secret below into an authenticator"
    PITO_TAG="$TAG" docker compose run --rm web bin/rails pito:tools:totp || \
      warn "TOTP enrollment failed — run './pito totp' once the stack is healthy."
  else
    warn "Existing install — keeping your data + TOTP enrollment (use './pito totp' to re-enroll)."
  fi

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
  CREDS_FRESH=1   # new secrets minted → fresh DB → enroll TOTP downstream
}

case "$MODE" in
  install)     do_install ;;
  service)     setup_systemd ;;
  cloudflared) setup_cloudflared ;;
esac
