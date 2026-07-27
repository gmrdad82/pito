#!/usr/bin/env sh
# script/install.sh — one-shot installer for the pito Docker stack.
#
#   curl -fsSL https://raw.githubusercontent.com/gmrdad82/pito/main/script/install.sh | sh
#
# No git clone, no host Ruby — everything runs against the prebuilt GHCR image
# (ghcr.io/gmrdad82/pito). It lands a self-contained install in ./pito-cli:
# docker-compose.yml + the pito-cli + .env + your own generated secrets.
#
# Pito chat installs on THIS machine and answers on localhost only. The
# installer asks which port to use, checks that nothing is already listening
# there, and wires the whole stack to it. There is no public-host question and
# no HTTPS step: putting a local port on the internet is a separate job with
# its own tools, and it is deliberately not this script's business.
#
# Flags:
#   --dir DIR          install location (default: ./pito-cli)
#   --port PORT        port to answer on (default: prompt, then 3028)
#   --tag TAG          image tag to run (default: latest)
#   --service-only     skip install; only (re)configure the systemd unit
#   --backup-timer-only  skip install; only (re)configure the daily backup timer
#   --link-only          skip install; only symlink pito-cli onto your PATH
#   --skip-pull          use the locally-present image (for testing a local build)
#   --edge               use the edge channel (image: latest, CLI from main)
#   --version VER        pin a specific release (e.g. v0.7.3)
#
# Re-running is safe and non-destructive: existing master.key / credentials are
# kept, the Postgres volume (channels, videos, games, /config API keys + webhooks)
# is never touched, and TOTP is NOT re-enrolled — your authenticator keeps working.
# To just update the image use `pito-cli update`; to (re)configure the service
# use `pito-cli service` (the installer symlinks `pito-cli` onto your PATH;
# otherwise run it as ./pito-cli from the install dir).

set -eu

REPO_RAW="https://raw.githubusercontent.com/gmrdad82/pito/main"
DIR="./pito-cli"
PORT=""
DEFAULT_PORT=3028
TAG="latest"
REF=""
CHANNEL=""
REQ_VERSION=""
MODE="install"
SKIP_PULL=""
CREDS_FRESH=0   # set to 1 by bootstrap_credentials only when it mints NEW secrets

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)              DIR="$2"; shift 2 ;;
    --port)             PORT="$2"; shift 2 ;;
    --tag)              TAG="$2"; shift 2 ;;
    --service-only)     MODE="service"; shift ;;
    --backup-timer-only) MODE="backup-timer"; shift ;;
    --link-only)         MODE="link"; shift ;;
    --edge)              CHANNEL="edge"; shift ;;
    --version)           REQ_VERSION="$2"; shift 2 ;;
    --skip-pull)         SKIP_PULL=1; shift ;;
    # --host is gone on purpose (5.0.0): pito installs on localhost and a
    # public address is no longer something this script knows how to make
    # true. Say so instead of quietly ignoring the flag.
    --host)
      echo "install: --host is gone — pito now installs on localhost only. Use --port PORT." >&2
      exit 1 ;;
    # Pattern-anchored (not a hardcoded line range) so a new flag line can
    # never silently fall off the help — same fix as bin/pito-cli's usage().
    -h|--help)          sed -n '2,/^#   --version/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# Add $1 to COMPOSE_PROFILES (comma list), dropping any token in $2
# (space-separated — the blue/green slot's mutually-exclusive sibling; ""
# for a plain additive token, which leaves the active deploy slot's own
# profile untouched).
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

# ── the port pito answers on ─────────────────────────────────────────────────
# Pito chat is a localhost service. Everything below is about ONE question —
# which port — asked once, checked before it is used, and then written into
# .env so every later `pito-cli update` keeps it.

# True when something is already listening on TCP port $1. Tries the tools a
# host is likely to have, in order, and gives up honestly rather than
# guessing: an unknown answer must not block an install.
#   0 = in use   1 = free   2 = could not tell
port_in_use() {
  p="$1"
  if have ss; then
    if ss -ltn 2>/dev/null | grep -qE "[:.]${p}[[:space:]]"; then return 0; fi
    return 1
  fi
  if have netstat; then
    if netstat -ltn 2>/dev/null | grep -qE "[:.]${p}[[:space:]]"; then return 0; fi
    return 1
  fi
  if have lsof; then
    if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then return 0; fi
    return 1
  fi
  return 2
}

# A port is 1-65535 and nothing else. Rejects "80a", "", "0", "99999".
valid_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# Ask for the port (unless --port already answered), validate it, and refuse
# one that is taken. Loops on a tty; without one it takes the default and
# fails loudly if that is occupied, because a non-interactive install that
# silently lands on a different port than it printed is worse than no install.
prompt_port() {
  # `retry` is the ONLY thing that lets the loop go round again, and it is
  # set exclusively by a successful read from the terminal. A piped install
  # (curl | sh with no tty) therefore gets exactly one attempt and a clear
  # error — never a spin.
  while : ; do
    retry=0
    if [ -z "$PORT" ]; then
      printf 'Port pito will answer on [%s]: ' "$DEFAULT_PORT"
      if read -r PORT </dev/tty; then
        retry=1
      else
        PORT=""
      fi
      if [ -z "$PORT" ]; then PORT="$DEFAULT_PORT"; fi
    fi

    if ! valid_port "$PORT"; then
      warn "'$PORT' is not a port number (1-65535)."
      if [ "$retry" = 0 ]; then die "Pick another with --port PORT."; fi
      PORT=""; continue
    fi

    port_in_use "$PORT" && rc=0 || rc=$?
    case "$rc" in
      0)
        warn "Something is already listening on port $PORT."
        if [ "$retry" = 0 ]; then die "Pick a free one with --port PORT."; fi
        PORT=""; continue ;;
      2)
        warn "Couldn't check port $PORT (no ss, netstat or lsof here) — carrying on."
        return 0 ;;
      *)
        say "Port $PORT is free — pito will answer at http://localhost:$PORT"
        return 0 ;;
    esac
  done
}

# The install dir's docker-compose.yml is a FETCHED artifact, not a repo file,
# so the installer is free to parameterise the one line that hardcodes the
# published port. Idempotent, and a no-op once the published compose file
# carries ${PITO_PORT} itself. script/update.sh re-applies it after every
# refresh — the fetch would otherwise put 3028 back.
apply_port_binding() {
  f="${1:-docker-compose.yml}"
  [ -f "$f" ] || return 0
  if grep -q 'PITO_PORT' "$f"; then return 0; fi
  if ! grep -q '"127\.0\.0\.1:3028:8080"' "$f"; then
    warn "Couldn't find the published-port line in $f — leaving it as it came."
    return 0
  fi
  tmp=$(mktemp)
  sed 's|"127\.0\.0\.1:3028:8080"|"127.0.0.1:${PITO_PORT:-3028}:8080"|' "$f" > "$tmp" && mv "$tmp" "$f"
}

# ── systemd unit (reboot persistence) ────────────────────────────────────────
setup_systemd() {
  say "Reboot-persistence (systemd)"
  printf 'Install a systemd unit so pito starts on boot? [u]ser / [s]ystem / [n]o: '
  read -r choice </dev/tty || choice="n"
  workdir="$PWD"
  unit_body() {
    # --remove-orphans on both legs: when an update changes the stack's shape
    # (e.g. the single-`web` → web-blue/web-green split), containers for
    # services no longer in docker-compose.yml must not linger holding ports
    # or spamming compose with orphan warnings.
    cat <<EOF
[Unit]
Description=pito (Docker Compose)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$workdir
ExecStart=/usr/bin/env docker compose up --remove-orphans
ExecStop=/usr/bin/env docker compose down --remove-orphans
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

# ── daily backup timer (system systemd timer) ────────────────────────────────
setup_backup_timer() {
  if ! have systemctl; then
    warn "systemd is required for the backup timer — skipping."
    return 0
  fi
  workdir="$PWD"
  user="$(id -un)"
  say "Daily backup timer (systemd)"
  sudo tee /etc/systemd/system/pito-backup.service >/dev/null <<EOF
[Unit]
Description=pito backup (database + assets)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=$user
WorkingDirectory=$workdir
ExecStart=$workdir/pito-cli backup
EOF
  sudo tee /etc/systemd/system/pito-backup.timer >/dev/null <<EOF
[Unit]
Description=Daily pito backup

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now pito-backup.timer
  say "pito-backup.timer enabled — daily at 03:00, keeping the newest 7 backups in ./backups (override with PITO_BACKUP_KEEP)."
}

# ── the one-release `pito` shim — linked only when nothing else owns `pito` ──
# `pito` is the terminal client's command name now (pito-tui ships its binary,
# its .deb and its Homebrew formula under it — and on Intel macOS that formula
# writes /usr/local/bin/pito, this exact path). Our shim is a one-release
# courtesy for fingers that still type `pito` for the operator CLI, so it must
# never win a fight it didn't pick: link it onto a free name, or over a shim we
# placed ourselves (a symlink to a `pito` sitting beside a `pito-cli` — an
# install dir of this stack; a Homebrew Cellar link can't match that). A `pito`
# already resolvable further down PATH (the client's .deb lands one in
# /usr/bin, which /usr/local/bin precedes) is left unshadowed for the same
# reason: losing the courtesy beats hiding the client behind a deprecation
# notice. This whole function goes when the shim does, next release.
# NOTE: kept byte-identical with script/update.sh's copy (both scripts run
# standalone via curl | sh, so they can't share a file) — a spec pins that.
link_pito_shim() {
  shim_dir="${PITO_BIN_DIR:-/usr/local/bin}"   # overridable so the spec can drive this
  shim_target="$shim_dir/pito"
  [ -f "$PWD/pito" ] || return 0
  if [ -e "$shim_target" ] || [ -L "$shim_target" ]; then
    shim_cur=$(readlink "$shim_target" 2>/dev/null || true)
    if [ "${shim_cur##*/}" != "pito" ] || [ ! -f "${shim_cur%/pito}/pito-cli" ]; then
      printf '%s\n' "!  $shim_target is not ours — left untouched (that's the pito terminal client). The operator CLI is 'pito-cli'." >&2
      return 0
    fi
  else
    shim_other=$(command -v pito 2>/dev/null || true)
    if [ -n "$shim_other" ] && [ "$shim_other" != "$shim_target" ]; then
      printf '%s\n' "!  'pito' already resolves to $shim_other — not shadowing it. The operator CLI is 'pito-cli'." >&2
      return 0
    fi
  fi
  sudo ln -sf "$PWD/pito" "$shim_target" 2>/dev/null || true
}

# ── put `pito-cli` on PATH ───────────────────────────────────────────────────────
# Symlink the install-dir CLI to /usr/local/bin/pito-cli so it runs as a bare
# `pito-cli` from anywhere, and (only when it's free — see above) link
# /usr/local/bin/pito to the one-release shim. bin/pito-cli resolves the
# symlink back to its install dir. Best effort: if sudo/PATH isn't available,
# fall back to ./pito-cli.
LINKED=0
link_cli() {
  src="$PWD/pito-cli"
  [ -f "$src" ] || { warn "pito-cli not found in $PWD — skipping PATH link."; return 0; }
  say "Linking pito-cli onto your PATH (/usr/local/bin/pito-cli)"
  if sudo ln -sf "$src" /usr/local/bin/pito-cli 2>/dev/null; then
    LINKED=1
    link_pito_shim
    say "Linked — you can now run 'pito-cli' from anywhere."
  else
    warn "Couldn't link to /usr/local/bin (no sudo / not writable). Run it as ./pito-cli from $PWD."
  fi
}

# ── version / channel resolution ─────────────────────────────────────────────
list_tags() {
  curl -fsSL "https://api.github.com/repos/gmrdad82/pito/tags?per_page=30" 2>/dev/null \
    | grep -oE '"name": *"v[0-9][^"]*"' \
    | sed -E 's/.*"(v[0-9][^"]*)".*/\1/' \
    | sort -Vr
}

resolve_version() {
  # Explicit version pin wins — use it as both the git ref and image tag.
  if [ -n "${REQ_VERSION:-}" ]; then
    REF="$REQ_VERSION"; TAG="${REQ_VERSION#v}"; return 0
  fi
  if [ "$CHANNEL" = "edge" ]; then REF="main"; TAG="latest"; return 0; fi
  # Interactive pick: show the 5 newest releases + edge option.
  tags=$(list_tags)
  newest=$(printf '%s\n' "$tags" | head -1)
  if [ -z "$tags" ]; then
    warn "Couldn't list releases (offline / API limit) — defaulting to edge (latest + main)."
    REF="main"; TAG="latest"; return 0
  fi
  echo "Available Pito versions:" >&2
  i=1; printf '%s\n' "$tags" | head -5 | while IFS= read -r t; do
    if [ "$t" = "$newest" ]; then printf '  %d) %s   stable (recommended)\n' "$i" "$t" >&2; else printf '  %d) %s   stable\n' "$i" "$t" >&2; fi
    i=$((i+1))
  done
  printf '  e) edge   (latest image + bleeding-edge CLI from main)\n' >&2
  printf 'Pick [1]: ' >&2
  read -r pick </dev/tty || pick=""
  case "$pick" in
    e|E) REF="main"; TAG="latest" ;;
    "")  REF="$newest"; TAG="${newest#v}" ;;
    *)   chosen=$(printf '%s\n' "$tags" | head -5 | sed -n "${pick}p")
         [ -z "$chosen" ] && chosen="$newest"
         REF="$chosen"; TAG="${chosen#v}" ;;
  esac
}

# ── full install ─────────────────────────────────────────────────────────────
do_install() {
  require_docker

  resolve_version
  REPO_RAW="https://raw.githubusercontent.com/gmrdad82/pito/$REF"
  say "Channel: $(if [ "$REF" = "main" ]; then echo "edge"; else echo "stable ($REF)"; fi) — image tag $TAG"

  say "Installing pito into $DIR"
  mkdir -p "$DIR/config"
  cd "$DIR"

  say "Fetching docker-compose.yml + the pito-cli CLI (+ pito shim) + the load balancer's config (no git clone)"
  curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml
  curl -fsSL "$REPO_RAW/bin/pito-cli" -o pito-cli && chmod +x pito-cli
  curl -fsSL "$REPO_RAW/bin/pito"     -o pito     && chmod +x pito
  curl -fsSL "$REPO_RAW/Caddyfile.lb" -o Caddyfile.lb

  # The one question: which port. Asked, checked, then wired everywhere —
  # .env for the app's own base URL, and the fetched compose file's published
  # port (apply_port_binding).
  prompt_port
  apply_port_binding docker-compose.yml
  env_set PITO_PORT "$PORT"
  env_set PITO_APP_BASE_URL "http://localhost:$PORT"
  env_set PITO_TAG "$TAG"
  env_set PITO_REF "$REF"
  # Fresh installs start life natively in the blue/green shape — always on
  # the blue slot (see script/deploy-flip.sh for how a later deploy flips
  # between the two). COMPOSE_PROFILES=blue is what makes a bare
  # `docker compose up`/`pull` (no service names) include web-blue and skip
  # the as-yet-unused web-green.
  env_set PITO_ACTIVE_SLOT blue
  env_set PITO_TAG_BLUE "$TAG"
  profile_set blue "blue green"

  if [ -n "$SKIP_PULL" ]; then
    warn "Skipping image pull (--skip-pull) — using the locally-present image."
  else
    say "Pulling the image (ghcr.io/gmrdad82/pito:$TAG)"
    docker compose pull
  fi

  bootstrap_credentials

  say "Starting the stack"
  docker compose up -d

  if [ "$CREDS_FRESH" = "1" ]; then
    say "Enrolling your login (TOTP) — scan the QR/secret below into an authenticator"
    docker compose run --rm web-blue bin/rails pito:totp || \
      warn "TOTP enrollment failed — run './pito-cli totp' once the stack is healthy."
  else
    warn "Existing install — keeping your data + TOTP enrollment (use './pito-cli totp' to re-enroll)."
  fi

  setup_systemd
  link_cli

  printf 'Install a daily backup timer (DB + assets → ./backups, keep 7)? [y/N]: '
  read -r choice </dev/tty || choice="n"
  case "$choice" in y|Y) setup_backup_timer ;; *) warn "Skipped backup timer (add later: pito-cli backup-schedule)." ;; esac

  say "Done. pito is at http://localhost:$PORT"
  if [ "$LINKED" = "1" ]; then
    echo "Manage it from anywhere:  pito-cli logs -f   pito-cli console   pito-cli update"
  else
    echo "Manage it from $DIR:  ./pito-cli logs -f   ./pito-cli console   ./pito-cli update"
  fi
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
  install)      do_install ;;
  service)      setup_systemd ;;
  backup-timer) setup_backup_timer ;;
  link)         link_cli ;;
esac
