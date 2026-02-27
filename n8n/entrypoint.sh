#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# RWR Group Slack LMS — n8n Entrypoint Script
# ═══════════════════════════════════════════════════════════════════════════
# This script:
#   1. Starts n8n in the background
#   2. Waits for the n8n API to be ready
#   3. On first boot: imports all workflows (in dependency order)
#   4. Patches supervisor-router's executeWorkflow node references
#   5. Activates all workflows
#   6. Brings n8n to the foreground
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[n8n-entrypoint]${NC} ✓ $*"; }
warn() { echo -e "${YELLOW}[n8n-entrypoint]${NC} ⚠ $*"; }
err()  { echo -e "${RED}[n8n-entrypoint]${NC} ✗ $*" >&2; }
info() { echo -e "[n8n-entrypoint] → $*"; }

FLAG_FILE="/home/node/.imported"
WORKFLOWS_DIR="/home/node/workflows"
N8N_API_URL="http://localhost:5678"
N8N_AUTH=$(echo -n "${N8N_BASIC_AUTH_USER:-admin}:${N8N_BASIC_AUTH_PASSWORD:-}" | base64)

# ─── Start n8n in the background ─────────────────────────────────────────────
info "Starting n8n in the background..."
n8n start &
N8N_PID=$!

# ─── Wait for n8n to be ready ─────────────────────────────────────────────────
info "Waiting for n8n API to be ready..."
MAX_WAIT=120
elapsed=0
until curl -sf "${N8N_API_URL}/healthz" > /dev/null 2>&1; do
  if [[ $elapsed -ge $MAX_WAIT ]]; then
    err "n8n did not become ready within ${MAX_WAIT}s"
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
  echo -n "."
done
echo
ok "n8n API is ready (${elapsed}s)"

# Give n8n a moment to finish internal initialization
sleep 3

# ─── Check if already imported ───────────────────────────────────────────────
if [[ -f "$FLAG_FILE" ]]; then
  ok "Workflows already imported (flag file exists) — skipping import"
else
  info "First boot detected — importing workflows..."

  # ─── Import workflows in strict dependency order ────────────────────────────
  # CRITICAL: supervisor-router.json MUST be imported LAST because it references
  # all other workflow IDs in its executeWorkflow nodes.
  IMPORT_ORDER=(
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

  imported=0
  skipped=0

  for workflow_file in "${IMPORT_ORDER[@]}"; do
    full_path="${WORKFLOWS_DIR}/${workflow_file}"

    if [[ ! -f "$full_path" ]]; then
      warn "Workflow file not found: ${workflow_file} — skipping"
      skipped=$((skipped + 1))
      continue
    fi

    info "Importing: ${workflow_file}"
    if n8n import:workflow --input="${full_path}" 2>&1; then
      ok "Imported: ${workflow_file}"
      imported=$((imported + 1))
    else
      warn "Failed to import: ${workflow_file} (continuing)"
    fi

    # Small delay between imports to prevent race conditions
    sleep 1
  done

  ok "Import complete: ${imported} imported, ${skipped} skipped"

  # ─── Patch supervisor-router's executeWorkflow references ──────────────────
  if [[ -f "/home/node/scripts/update-workflow-ids.py" ]]; then
    info "Patching supervisor-router workflow ID references..."
    python3 /home/node/scripts/update-workflow-ids.py \
      --n8n-url "${N8N_API_URL}" \
      --auth "${N8N_BASIC_AUTH_USER:-admin}:${N8N_BASIC_AUTH_PASSWORD:-}" \
      && ok "Workflow IDs patched" \
      || warn "Workflow ID patching failed (supervisor-router may have stale IDs)"
  fi

  # ─── Activate all workflows ─────────────────────────────────────────────────
  info "Activating all workflows..."

  WORKFLOW_IDS=$(curl -sf \
    -H "Authorization: Basic ${N8N_AUTH}" \
    "${N8N_API_URL}/api/v1/workflows" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    ids = [str(w['id']) for w in data.get('data', [])]
    print(' '.join(ids))
except Exception as e:
    print('', end='')
" || echo "")

  activated=0
  for wf_id in $WORKFLOW_IDS; do
    if curl -sf -X PATCH \
      -H "Authorization: Basic ${N8N_AUTH}" \
      -H "Content-Type: application/json" \
      -d '{"active": true}' \
      "${N8N_API_URL}/api/v1/workflows/${wf_id}" > /dev/null 2>&1; then
      activated=$((activated + 1))
    fi
  done

  ok "Activated ${activated} workflow(s)"

  # ─── Write flag file to prevent re-import on container restart ──────────────
  echo "Imported on: $(date -u)" > "$FLAG_FILE"
  ok "Import flag written — will not re-import on next container start"

fi

# ─── Bring n8n to the foreground ─────────────────────────────────────────────
info "Handing control to n8n (PID: ${N8N_PID})..."
wait $N8N_PID
