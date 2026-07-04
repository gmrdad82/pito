#!/usr/bin/env sh
# script/hetzner.sh — provision a Hetzner Cloud server ready to run pito.
#
#   pito hetzner provision   create ssh-key + firewall + server (idempotent)
#   pito hetzner info        show the server's status + IP
#
# Flags (provision):
#   --name NAME        server name            (default: pito-prod)
#   --type TYPE        server type            (default: cx23 — 2 vCPU x86 / 4GB)
#   --image IMAGE      OS image               (default: ubuntu-26.04)
#   --location LOC     datacenter location    (default: fsn1)
#   --ssh-pubkey FILE  public key to install  (default: ~/.ssh/id_ed25519.pub)
#
# Needs the hcloud CLI (https://github.com/hetznercloud/cli) with a working
# token: either `hcloud context create <name>` (recommended; stored 0600 in
# ~/.config/hcloud/cli.toml) or the HCLOUD_TOKEN env var. This script never
# reads, stores, or prints the token itself.
#
# Provisioning is API-side only — nothing on this machine changes. The server
# boots with cloud-init: Docker (get.docker.com), a 2G swapfile, password SSH
# off, unattended upgrades on. Install pito on it afterwards (see the printed
# next steps). x86 (cx*) types are deliberate for migrations: Docker volumes
# copy bit-for-bit from an x86 laptop; ARM (cax*) would need a pg_dump leg.

set -eu

NAME="pito-prod"
TYPE="cx23"
IMAGE="ubuntu-26.04"
LOCATION="fsn1"
SSH_PUBKEY=""
FIREWALL="pito-fw"

say()  { printf '\n\033[1;34m→ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m!  %s\033[0m\n' "$1" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Print the whole leading comment block (no hardcoded line ranges — they rot).
usage() { awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; }

CMD="${1:-}"
[ $# -gt 0 ] && shift || true

while [ $# -gt 0 ]; do
  case "$1" in
    --name)       NAME="$2"; shift 2 ;;
    --type)       TYPE="$2"; shift 2 ;;
    --image)      IMAGE="$2"; shift 2 ;;
    --location)   LOCATION="$2"; shift 2 ;;
    --ssh-pubkey) SSH_PUBKEY="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) die "unknown flag '$1' (see: pito hetzner --help)" ;;
  esac
done

require_hcloud() {
  have hcloud || die "the hcloud CLI is required. Arch: sudo pacman -S hcloud — then: hcloud context create pito (paste your API token)."
  # Cheap authenticated call to fail fast with hcloud's own message when the
  # token is missing/expired, instead of half-way through provisioning.
  hcloud server-type list -o noheader >/dev/null 2>&1 || \
    die "hcloud can't reach the API — set up a token first: hcloud context create pito (or export HCLOUD_TOKEN)."
}

# Pick the default public key. A DEDICATED key for this server is preferred
# (~/.ssh/pito-hetzner.pub — create with: ssh-keygen -t ed25519 -f ~/.ssh/pito-hetzner)
# so the personal default key never has to leave the laptop; the generic keys
# are fallbacks for self-hosters who don't care to separate them.
resolve_pubkey() {
  [ -n "$SSH_PUBKEY" ] && { [ -f "$SSH_PUBKEY" ] || die "no such public key: $SSH_PUBKEY"; return 0; }
  for k in "$HOME/.ssh/pito-hetzner.pub" "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    [ -f "$k" ] && { SSH_PUBKEY="$k"; return 0; }
  done
  die "no SSH public key found (~/.ssh/pito-hetzner.pub, id_ed25519.pub, or id_rsa.pub) — pass one with --ssh-pubkey."
}

# ── provision (idempotent: each resource is reused when it already exists) ───
provision() {
  require_hcloud
  resolve_pubkey

  hcloud image list -o noheader -o columns=name 2>/dev/null | grep -qx "$IMAGE" || \
    die "image '$IMAGE' not found (hcloud image list | grep ubuntu) — pass one with --image."

  key_name="pito-$(id -un)"
  if hcloud ssh-key describe "$key_name" >/dev/null 2>&1; then
    say "SSH key '$key_name' already registered — reusing."
  else
    say "Registering SSH key '$key_name' ($SSH_PUBKEY)"
    hcloud ssh-key create --name "$key_name" --public-key-from-file "$SSH_PUBKEY"
  fi

  if hcloud firewall describe "$FIREWALL" >/dev/null 2>&1; then
    say "Firewall '$FIREWALL' already exists — reusing (verify rules: 22, 80, 443 in)."
  else
    say "Creating firewall '$FIREWALL' (inbound 22, 80, 443 only)"
    hcloud firewall create --name "$FIREWALL" >/dev/null
    for port in 22 80 443; do
      hcloud firewall add-rule "$FIREWALL" --direction in --protocol tcp --port "$port" \
        --source-ips 0.0.0.0/0 --source-ips ::/0
    done
  fi

  if hcloud server describe "$NAME" >/dev/null 2>&1; then
    warn "Server '$NAME' already exists — nothing created. Its IP:"
    hcloud server ip "$NAME"
    return 0
  fi

  # cloud-init: everything the box needs before pito lands. Password SSH is
  # off from first boot; Docker comes from get.docker.com (includes compose).
  tmp_init=$(mktemp)
  cat > "$tmp_init" <<'EOF'
#cloud-config
package_update: true
packages: [curl, unattended-upgrades]
swap:
  filename: /swapfile
  size: 2G
ssh_pwauth: false
runcmd:
  - curl -fsSL https://get.docker.com | sh
  - systemctl enable --now docker
  - dpkg-reconfigure -f noninteractive unattended-upgrades
EOF

  say "Creating server '$NAME' ($TYPE, $IMAGE, $LOCATION) — billing starts now"
  hcloud server create \
    --name "$NAME" --type "$TYPE" --image "$IMAGE" --location "$LOCATION" \
    --ssh-key "$key_name" --firewall "$FIREWALL" \
    --user-data-from-file "$tmp_init"
  rm -f "$tmp_init"

  ip=$(hcloud server ip "$NAME")
  cat <<EOF

Server '$NAME' is up at $ip. Next steps:
  1) DNS: point your domain's A record at $ip
  2) Wait ~2 min for cloud-init (Docker install), then: ssh root@$ip
  3) Install pito on it (https://github.com/gmrdad82/pito#install), pick
     Caddy at the HTTPS prompt — or run ./pito caddy after the install
  4) Optional disk-level backups (+20%%): hcloud server enable-backup $NAME
Rescale later with: hcloud server change-type $NAME <type> --keep-disk
(NEVER grow the root disk in a rescale — it blocks downscaling; attach a
Hetzner Volume instead when space runs out.)
EOF
}

info() {
  require_hcloud
  hcloud server describe "$NAME" 2>/dev/null || {
    warn "No server named '$NAME' (override with --name). Servers on this project:"
    hcloud server list
    return 0
  }
  printf '\nIP: '
  hcloud server ip "$NAME"
}

case "$CMD" in
  provision)      provision ;;
  info|status|ip) info ;;
  ""|-h|--help|help) usage ;;
  *) die "unknown subcommand '$CMD' — use: provision | info" ;;
esac
