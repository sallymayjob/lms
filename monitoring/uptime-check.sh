#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# RWR Group Slack LMS — Uptime / Webhook Health Monitor
# ═══════════════════════════════════════════════════════════════════════════
# Performs HTTP health checks on all LMS webhook endpoints.
# Suitable for use with cron or external monitoring services.
#
# Usage: ./monitoring/uptime-check.sh
# Exit code: 0 = all OK, 1 = one or more checks failed
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILURES=0
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Load domain from .env if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${PROJECT_DIR}/.env" ]]; then
  set -o allexport
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/.env"
  set +o allexport
fi

DOMAIN="${DOMAIN:-localhost}"
BASE_URL="https://${DOMAIN}"

echo "RWR LMS Uptime Check — ${TIMESTAMP}"
echo "Domain: ${DOMAIN}"
echo "────────────────────────────────────────"

# Helper: check a single endpoint
check() {
  local name="$1"
  local url="$2"
  local method="${3:-GET}"

  local http_code
  local start_ms
  local end_ms
  local elapsed_ms

  start_ms=$(date +%s%3N 2>/dev/null || date +%s)

  if [[ "$method" == "POST" ]]; then
    http_code=$(curl -sk --max-time 10 -o /dev/null -w "%{http_code}" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"_uptime_check": true}' \
      "$url" 2>/dev/null || echo "000")
  else
    http_code=$(curl -sk --max-time 10 -o /dev/null -w "%{http_code}" \
      "$url" 2>/dev/null || echo "000")
  fi

  end_ms=$(date +%s%3N 2>/dev/null || date +%s)
  elapsed_ms=$((end_ms - start_ms))

  # Connection refused = outage
  if [[ "$http_code" == "000" ]]; then
    echo -e "  ${RED}✗ FAIL${NC}  ${name} (connection refused) [${elapsed_ms}ms]"
    FAILURES=$((FAILURES + 1))
  else
    # Any HTTP response = endpoint reachable
    echo -e "  ${GREEN}✓ OK${NC}    ${name} (HTTP ${http_code}) [${elapsed_ms}ms]"
  fi
}

echo ""
echo "Core Services:"
check "n8n Healthz"         "${BASE_URL}/healthz"                  "GET"
check "n8n Editor"          "${BASE_URL}/"                         "GET"

echo ""
echo "Delivery Layer Webhooks:"
check "Supervisor Router"   "${BASE_URL}/webhook/supervisor"       "POST"
check "Slack Interactions"  "${BASE_URL}/webhook/slack-interactions" "POST"
check "Backup Agent"        "${BASE_URL}/webhook/backup"           "POST"

echo ""
echo "Content Factory Webhooks:"
check "Lesson Edit Detect"  "${BASE_URL}/webhook/lesson-edit-detect" "POST"
check "Lesson Publisher"    "${BASE_URL}/webhook/publish-lesson"   "POST"

echo ""
echo "────────────────────────────────────────"
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}All ${BASH_REMATCH[0]:-} checks passed${NC}"
  exit 0
else
  echo -e "${RED}${FAILURES} check(s) FAILED${NC}"
  exit 1
fi
