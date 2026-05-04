#!/usr/bin/env bash
#
# pull-claude-config.sh
#
# Mirror Pito-relevant agent / command / skill files FROM ~/.claude/ INTO this
# repo at .claude-config/. Run this after editing an agent in
# the Claude Code UI or hand-editing a file under ~/.claude/ that you want
# versioned.
#
# Behavior:
#   - rsync with --delete, scoped per subfolder. Files in the repo that no
#     longer exist in ~/.claude/ AND match the allow-list are removed.
#   - Only files that match the Pito allow-list are mirrored. Personal /
#     unrelated files in ~/.claude/ are left alone.
#   - Idempotent. Safe to run repeatedly.
#   - Prints every file copied or deleted.
#
# Usage:
#   ./pull-claude-config.sh            normal run
#   ./pull-claude-config.sh --dry-run  preview without writing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SRC_HOME="${HOME}/.claude"
DEST_REPO="${REPO_ROOT}/.claude-config"

DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="--dry-run"
fi

# The nine named agent files we mirror, plus anything matching pito-*.
ALLOWED_AGENTS=(
  "architect-spec.md"
  "rails-impl.md"
  "mcp-impl.md"
  "cli-impl.md"
  "website-impl.md"
  "reviewer.md"
  "security-auditor.md"
  "docs-keeper.md"
  "audit-state.md"
)

echo "pull-claude-config.sh"
echo "  source: ${SRC_HOME}"
echo "  dest:   ${DEST_REPO}"
[[ -n "${DRY_RUN}" ]] && echo "  mode:   DRY RUN (no changes)"
echo ""

if [[ ! -d "${SRC_HOME}" ]]; then
  echo "error: ${SRC_HOME} does not exist. Nothing to pull."
  exit 1
fi

mkdir -p "${DEST_REPO}/agents" "${DEST_REPO}/commands" "${DEST_REPO}/skills"

#
# 1) Agents — explicit allow-list of named files plus pito-* prefix.
#
echo "[1/3] agents"
if [[ -d "${SRC_HOME}/agents" ]]; then
  RSYNC_INCLUDES=()
  for name in "${ALLOWED_AGENTS[@]}"; do
    RSYNC_INCLUDES+=( "--include=${name}" )
  done
  RSYNC_INCLUDES+=( "--include=pito-*.md" "--exclude=*" )

  rsync -av ${DRY_RUN} --delete \
    "${RSYNC_INCLUDES[@]}" \
    "${SRC_HOME}/agents/" "${DEST_REPO}/agents/"
else
  echo "  (no ${SRC_HOME}/agents directory — skipping)"
fi
echo ""

#
# 2) Commands — only project-relevant slash commands. Allow pito-* and a
#    short list of known shared commands. Edit COMMAND_ALLOWED below to add.
#
echo "[2/3] commands"
COMMAND_ALLOWED=(
  "code-review.md"
  "simplify.md"
  "security-review.md"
)
if [[ -d "${SRC_HOME}/commands" ]]; then
  RSYNC_INCLUDES=()
  for name in "${COMMAND_ALLOWED[@]}"; do
    RSYNC_INCLUDES+=( "--include=${name}" )
  done
  RSYNC_INCLUDES+=( "--include=pito-*.md" "--exclude=*" )

  rsync -av ${DRY_RUN} --delete \
    "${RSYNC_INCLUDES[@]}" \
    "${SRC_HOME}/commands/" "${DEST_REPO}/commands/"
else
  echo "  (no ${SRC_HOME}/commands directory — skipping)"
fi
echo ""

#
# 3) Skills — only pito-* skills. Project skills live alongside agents; if
#    none exist this is a no-op.
#
echo "[3/3] skills"
if [[ -d "${SRC_HOME}/skills" ]]; then
  rsync -av ${DRY_RUN} --delete \
    --include="pito-*/" --include="pito-*/**" --exclude="*" \
    "${SRC_HOME}/skills/" "${DEST_REPO}/skills/"
else
  echo "  (no ${SRC_HOME}/skills directory — skipping)"
fi
echo ""

echo "pull-claude-config.sh: done."
