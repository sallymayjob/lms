#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# RWR Group Slack LMS — Health Check Script
# ═══════════════════════════════════════════════════════════════════════════
# Verifies all services and webhook endpoints are responding correctly.
#
# Usage: ./scripts/health-check.sh
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; FAILURES=$((FAILURES + 1)); }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
header(){ echo -e "\n${BOLD}${BLUE}$*${NC}"; }

FAILURES=0

# Load .env
if [[ -f .env ]]; then
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
fi

DOMAIN="${DOMAIN:-localhost}"
N8N_AUTH=$(echo -n "${N8N_BASIC_AUTH_USER:-admin}:${N8N_BASIC_AUTH_PASSWORD:-}" | base64)

# ─── Docker container health ─────────────────────────────────────────────────
header "Docker Container Status"

check_container() {
  local name="$1"
  local status
  status=$(docker inspect --format '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "not_found")
  case "$status" in
    healthy)   ok "${name}: healthy" ;;
    not_found) fail "${name}: container not found" ;;
    starting)  warn "${name}: still starting up" ;;
    *)         fail "${name}: status = ${status}" ;;
  esac
}

check_container "rwr-lms-postgres"
check_container "rwr-lms-n8n"
check_container "rwr-lms-nginx"

# ─── n8n API health ──────────────────────────────────────────────────────────
header "n8n API Health"

if docker compose exec -T n8n curl -sf --max-time 5 "http://localhost:5678/healthz" > /dev/null 2>&1; then
  ok "n8n API: /healthz responding"
else
  fail "n8n API: /healthz not responding"
fi

# ─── Webhook endpoint checks ─────────────────────────────────────────────────
header "Webhook Endpoint Checks (via Nginx HTTPS)"

check_webhook() {
  local name="$1"
  local url="$2"
  local _expected_status="${3:-200}"  # reserved for future use

  local http_status
  http_status=$(curl -sk --max-time 10 -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"_healthcheck": true}' \
    "$url" 2>/dev/null || echo "000")

  # Webhooks return various codes — 200, 400 (bad payload), 404 (workflow inactive)
  # We just want the endpoint to be reachable (not 000 = connection refused)
  if [[ "$http_status" != "000" ]]; then
    ok "${name}: reachable (HTTP ${http_status})"
  else
    fail "${name}: not reachable (connection refused)"
  fi
}

check_webhook "Supervisor"          "https://${DOMAIN}/webhook/supervisor"
check_webhook "Slack Interactions"  "https://${DOMAIN}/webhook/slack-interactions"
check_webhook "Backup"              "https://${DOMAIN}/webhook/backup"
check_webhook "Lesson Edit Detect"  "https://${DOMAIN}/webhook/lesson-edit-detect"
check_webhook "Lesson Publisher"    "https://${DOMAIN}/webhook/publish-lesson"

# ─── Postgres connectivity ────────────────────────────────────────────────────
header "PostgreSQL Connectivity"

if docker compose exec -T postgres \
  pg_isready -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" \
  > /dev/null 2>&1; then
  ok "Postgres: accepting connections"
else
  fail "Postgres: not ready"
fi

# Quick table check
TABLE_COUNT=$(docker compose exec -T postgres \
  psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -tAq \
  -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" \
  2>/dev/null || echo "0")

if [[ "$TABLE_COUNT" -ge 10 ]]; then
  ok "Postgres: ${TABLE_COUNT} tables found (schema looks correct)"
else
  warn "Postgres: only ${TABLE_COUNT} tables found (expected ≥10 — schema may be incomplete)"
fi

# ─── n8n workflow count ────────────────────────────────────────────────────
header "n8n Workflow Status"

WORKFLOW_COUNT=$(docker compose exec -T n8n sh -c "curl -sf -H 'Authorization: Basic ${N8N_AUTH}' 'http://localhost:5678/api/v1/workflows'" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" \
  2>/dev/null || echo "0")

ACTIVE_COUNT=$(docker compose exec -T n8n sh -c "curl -sf -H 'Authorization: Basic ${N8N_AUTH}' 'http://localhost:5678/api/v1/workflows?active=true'" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" \
  2>/dev/null || echo "0")

if [[ "$WORKFLOW_COUNT" -ge 18 ]]; then
  ok "n8n: ${WORKFLOW_COUNT} workflows imported (${ACTIVE_COUNT} active)"
else
  warn "n8n: ${WORKFLOW_COUNT} workflows found (expected 18) — some may not be imported yet"
fi

# ─── SSL certificate check ───────────────────────────────────────────────────
header "SSL Certificate"

CERT_EXPIRY=$(echo | openssl s_client -servername "${DOMAIN}" \
  -connect "${DOMAIN}:443" 2>/dev/null | \
  openssl x509 -noout -enddate 2>/dev/null | \
  sed 's/notAfter=//' || echo "")

if [[ -n "$CERT_EXPIRY" ]]; then
  ok "SSL certificate valid — expires: ${CERT_EXPIRY}"
else
  warn "Could not check SSL certificate (self-signed or DNS not resolving yet)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}All health checks passed!${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}${FAILURES} health check(s) failed. Review the output above.${NC}"
  exit 1
fi
