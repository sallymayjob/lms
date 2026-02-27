#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# RWR Group Slack LMS — Idempotent Workflow Import Script
# ═══════════════════════════════════════════════════════════════════════════
# Imports all n8n workflow JSON files in the correct dependency order.
# Safe to run multiple times — n8n deduplicates by workflow name.
#
# Usage: ./scripts/import-workflows.sh
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
info() { echo -e "${BLUE}→${NC} $*"; }

WORKFLOWS_DIR="./n8n/workflows"
N8N_CONTAINER="rwr-lms-n8n"

# Verify n8n container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${N8N_CONTAINER}$"; then
  err "n8n container '${N8N_CONTAINER}' is not running."
  err "Start with: docker compose up -d"
  exit 1
fi

# ─── Import order — dependency graph ─────────────────────────────────────────
# CRITICAL: supervisor-router.json MUST be last — it has executeWorkflow refs
# to all other agents and those IDs must exist before the router is imported.

declare -a IMPORT_ORDER=(
  "agent-02-quiz-master.json"
  "agent-03-tutor.json"
  "agent-04-progress-tracker.json"
  "agent-05-course-catalog.json"
  "agent-06-help.json"
  "agent-07-certification.json"
  "agent-08-enrollment-manager.json"
  "agent-09-gap-analyst.json"
  "agent-10-unenroll.json"
  "agent-11-proactive-nudge.json"
  "agent-12-reporting-agent.json"
  "agent-13-onboarding-agent.json"
  "agent-14-backup-to-sheets.json"
  "agent-15-assignment-intake.json"
  "agent-16-lesson-edit-detector.json"
  "agent-17-gemini-retester.json"
  "agent-18-lesson-publisher.json"
  "supervisor-router.json"
)

echo ""
info "Starting workflow import (${#IMPORT_ORDER[@]} files)"
echo ""

imported=0
skipped=0
failed=0

for workflow_file in "${IMPORT_ORDER[@]}"; do
  full_path="${WORKFLOWS_DIR}/${workflow_file}"

  if [[ ! -f "$full_path" ]]; then
    warn "File not found: ${workflow_file} — skipping"
    skipped=$((skipped + 1))
    continue
  fi

  info "Importing: ${workflow_file}"

  if docker compose exec -T n8n \
    n8n import:workflow \
    --input="/home/node/workflows/${workflow_file}" \
    2>&1; then
    ok "Imported: ${workflow_file}"
    imported=$((imported + 1))
  else
    warn "Failed to import: ${workflow_file}"
    failed=$((failed + 1))
  fi

  # Brief pause to prevent race conditions in n8n DB writes
  sleep 1
done

echo ""
echo -e "Import summary:"
echo -e "  ${GREEN}Imported:${NC} ${imported}"
echo -e "  ${YELLOW}Skipped:${NC}  ${skipped}"
if [[ $failed -gt 0 ]]; then
  echo -e "  ${RED}Failed:${NC}   ${failed}"
  echo ""
  warn "Some imports failed. Check n8n logs: docker compose logs n8n"
  exit 1
fi

echo ""
ok "All workflows imported successfully"
