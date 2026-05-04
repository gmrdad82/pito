#!/usr/bin/env bash
#
# install-claude-config.sh
#
# Install Pito agent / command / skill files FROM this repo INTO ~/.claude/.
# Run this on a fresh laptop after cloning pito-dev-kb, or after pulling
# upstream changes to .claude-config/.
#
# Safety behavior:
#   - Refuses to overwrite a file in ~/.claude/ that is NEWER than the repo
#     copy (mtime comparison) unless --force is passed.
#   - Prints every file that would change. Without --yes, prompts for
#     confirmation before applying.
#   - Never deletes files from ~/.claude/. Only creates and updates.
#   - Idempotent.
#
# Usage:
#   ./install-claude-config.sh                normal run, prompts before applying
#   ./install-claude-config.sh --yes          apply without prompting
#   ./install-claude-config.sh --force        overwrite even when ~/.claude/ is newer
#   ./install-claude-config.sh --yes --force  unattended, full overwrite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SRC_REPO="${REPO_ROOT}/.claude-config"
DEST_HOME="${HOME}/.claude"

ASSUME_YES=0
FORCE=0
for arg in "$@"; do
  case "${arg}" in
    --yes)   ASSUME_YES=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "error: unknown argument '${arg}'" >&2
      exit 2
      ;;
  esac
done

echo "install-claude-config.sh"
echo "  source: ${SRC_REPO}"
echo "  dest:   ${DEST_HOME}"
[[ "${ASSUME_YES}" -eq 1 ]] && echo "  mode:   --yes (no prompt)"
[[ "${FORCE}"      -eq 1 ]] && echo "  mode:   --force (ignore newer dest mtime)"
echo ""

if [[ ! -d "${SRC_REPO}" ]]; then
  echo "error: ${SRC_REPO} does not exist. Run from a checkout of pito-dev-kb." >&2
  exit 1
fi

mkdir -p "${DEST_HOME}/agents" "${DEST_HOME}/commands" "${DEST_HOME}/skills"

# Build a plan: list of (action, src, dest) tuples, then apply if confirmed.
declare -a PLAN_ACTIONS=()
declare -a PLAN_SRCS=()
declare -a PLAN_DESTS=()
declare -a SKIPPED_NEWER=()

plan_one() {
  local src="$1"
  local dest="$2"
  local rel="$3"

  if [[ ! -e "${dest}" ]]; then
    PLAN_ACTIONS+=( "CREATE" )
    PLAN_SRCS+=( "${src}" )
    PLAN_DESTS+=( "${dest}" )
    return
  fi

  if cmp -s "${src}" "${dest}"; then
    return
  fi

  local src_mtime dest_mtime
  src_mtime=$(stat -c %Y "${src}")
  dest_mtime=$(stat -c %Y "${dest}")

  if [[ "${dest_mtime}" -gt "${src_mtime}" && "${FORCE}" -ne 1 ]]; then
    SKIPPED_NEWER+=( "${rel}" )
    return
  fi

  PLAN_ACTIONS+=( "UPDATE" )
  PLAN_SRCS+=( "${src}" )
  PLAN_DESTS+=( "${dest}" )
}

scan_dir() {
  local sub="$1"
  local src_dir="${SRC_REPO}/${sub}"
  local dest_dir="${DEST_HOME}/${sub}"

  [[ -d "${src_dir}" ]] || return 0

  while IFS= read -r -d '' src; do
    local rel="${src#${SRC_REPO}/}"
    local dest="${DEST_HOME}/${rel}"
    mkdir -p "$(dirname "${dest}")"
    plan_one "${src}" "${dest}" "${rel}"
  done < <(find "${src_dir}" -type f -print0)
}

scan_dir "agents"
scan_dir "commands"
scan_dir "skills"

if [[ "${#PLAN_ACTIONS[@]}" -eq 0 && "${#SKIPPED_NEWER[@]}" -eq 0 ]]; then
  echo "Nothing to do — ${DEST_HOME} is already in sync."
  exit 0
fi

if [[ "${#PLAN_ACTIONS[@]}" -gt 0 ]]; then
  echo "Planned changes:"
  for i in "${!PLAN_ACTIONS[@]}"; do
    echo "  ${PLAN_ACTIONS[$i]}  ${PLAN_DESTS[$i]}"
  done
  echo ""
fi

if [[ "${#SKIPPED_NEWER[@]}" -gt 0 ]]; then
  echo "Skipped (destination is newer; pass --force to overwrite):"
  for rel in "${SKIPPED_NEWER[@]}"; do
    echo "  SKIP    ${DEST_HOME}/${rel}"
  done
  echo ""
fi

if [[ "${#PLAN_ACTIONS[@]}" -eq 0 ]]; then
  echo "No applicable changes after skip filter. Re-run with --force to override."
  exit 0
fi

if [[ "${ASSUME_YES}" -ne 1 ]]; then
  read -r -p "Apply these changes? [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

for i in "${!PLAN_ACTIONS[@]}"; do
  install -D -m 0644 "${PLAN_SRCS[$i]}" "${PLAN_DESTS[$i]}"
  echo "  ${PLAN_ACTIONS[$i]}  ${PLAN_DESTS[$i]}"
done

echo ""
echo "install-claude-config.sh: done."
