#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# RWR Group Slack LMS — Claude Code Session Start Hook
# ═══════════════════════════════════════════════════════════════════════════
# Installs dev tools needed for linting and validating this repo:
#   - shellcheck: lint Bash scripts (setup.sh, health-check.sh, etc.)
#   - python3-requests: required by scripts/update-workflow-ids.py
#   - jq: JSON validation and inspection
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

# Only run in remote (web) Claude Code sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

echo "RWR LMS session-start hook running..."

# ─── shellcheck (Bash linter) ─────────────────────────────────────────────────
if ! command -v shellcheck &>/dev/null; then
  echo "Installing shellcheck..."
  apt-get install -y --no-install-recommends shellcheck 2>&1 | tail -2
else
  echo "shellcheck already installed: $(shellcheck --version | head -1)"
fi

# ─── jq (JSON inspector) ──────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Installing jq..."
  apt-get install -y --no-install-recommends jq 2>&1 | tail -2
else
  echo "jq already installed: $(jq --version)"
fi

# ─── Python requests (used by update-workflow-ids.py) ────────────────────────
if ! python3 -c "import requests" &>/dev/null; then
  echo "Installing python3 requests..."
  pip3 install --quiet requests
else
  echo "python3 requests already installed"
fi

echo "RWR LMS session-start hook complete."
