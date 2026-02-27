#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# RWR Group Slack LMS — One-Command Setup Script
# ═══════════════════════════════════════════════════════════════════════════
# Usage: chmod +x setup.sh && ./setup.sh
# Requirements: Docker Engine 24+, Docker Compose v2, curl, openssl
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Colours ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
err()  { echo -e "${RED}✗ ERROR:${NC} $*" >&2; }
warn() { echo -e "${YELLOW}⚠ WARNING:${NC} $*"; }
info() { echo -e "${BLUE}→${NC} $*"; }
header() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n"; }

# ─── Step 1: Pre-flight checks ───────────────────────────────────────────────
header "Step 1/10 — Pre-flight checks"

check_command() {
  if ! command -v "$1" &>/dev/null; then
    err "$1 is not installed. Please install it first."
    case "$1" in
      docker)   info "Install Docker: https://docs.docker.com/engine/install/" ;;
      curl)     info "Install curl: apt-get install -y curl" ;;
      openssl)  info "Install openssl: apt-get install -y openssl" ;;
      python3)  info "Install python3: apt-get install -y python3" ;;
    esac
    exit 1
  fi
  ok "$1 found"
}

check_command docker
check_command curl
check_command openssl
check_command python3

# Check Docker Compose v2
if docker compose version &>/dev/null; then
  ok "Docker Compose v2 found"
else
  err "Docker Compose v2 not found. Install the Docker Compose plugin."
  info "See: https://docs.docker.com/compose/install/"
  exit 1
fi

# Check Docker daemon is running
if ! docker info &>/dev/null; then
  err "Docker daemon is not running. Start it first: systemctl start docker"
  exit 1
fi
ok "Docker daemon is running"

# ─── Step 2: Environment setup ───────────────────────────────────────────────
header "Step 2/10 — Environment setup"

# Copy template if .env doesn't exist
if [[ ! -f .env ]]; then
  if [[ -f .env.template ]]; then
    cp .env.template .env
    ok "Created .env from .env.template"
  else
    err ".env.template not found. Cannot create .env."
    exit 1
  fi
else
  ok ".env already exists — using existing values as defaults"
fi

# Source existing .env to get current values
set +u
# shellcheck disable=SC1091
source .env 2>/dev/null || true
set -u

# Helper: prompt for a value with a default
prompt_var() {
  local var_name="$1"
  local prompt_text="$2"
  local default_val="${3:-}"
  local is_secret="${4:-false}"
  local current_val="${!var_name:-${default_val}}"

  if [[ "$is_secret" == "true" ]]; then
    if [[ -n "$current_val" ]]; then
      echo -e "  ${prompt_text} ${YELLOW}[already set — press Enter to keep]${NC}:"
      read -r -s input
      echo
      [[ -n "$input" ]] && eval "$var_name=\"$input\"" || eval "$var_name=\"$current_val\""
    else
      echo -e "  ${prompt_text}:"
      read -r -s input
      echo
      eval "$var_name=\"$input\""
    fi
  else
    if [[ -n "$current_val" ]]; then
      echo -e "  ${prompt_text} ${YELLOW}[${current_val}]${NC}:"
    else
      echo -e "  ${prompt_text} ${YELLOW}[${default_val}]${NC}:"
    fi
    read -r input
    if [[ -n "$input" ]]; then
      eval "$var_name=\"$input\""
    elif [[ -n "$current_val" ]]; then
      eval "$var_name=\"$current_val\""
    else
      eval "$var_name=\"$default_val\""
    fi
  fi
}

echo -e "\n${BOLD}Configure your LMS environment:${NC}"
echo -e "Press Enter to accept the current/default value shown in [brackets].\n"

# Domain
prompt_var DOMAIN "Domain name for LMS (e.g. lms.example.com)" "lms.yourdomain.com"
if [[ "$DOMAIN" == "lms.yourdomain.com" ]] || [[ -z "$DOMAIN" ]]; then
  err "You must set a real domain name. Edit .env and run setup.sh again."
  exit 1
fi

# SSL email
prompt_var SSL_EMAIL "Email for SSL certificate" "admin@${DOMAIN}"

# Slack
echo ""
info "── Slack Configuration ──"
prompt_var SLACK_BOT_TOKEN "Slack Bot Token (xoxb-...)" "" "true"
if [[ -z "${SLACK_BOT_TOKEN:-}" ]] || [[ "${SLACK_BOT_TOKEN}" != xoxb-* ]]; then
  err "SLACK_BOT_TOKEN must start with 'xoxb-'"
  exit 1
fi

prompt_var SLACK_SIGNING_SECRET "Slack Signing Secret (32-char hex)" "" "true"
if [[ ${#SLACK_SIGNING_SECRET} -ne 32 ]]; then
  err "SLACK_SIGNING_SECRET must be exactly 32 characters"
  exit 1
fi

prompt_var SLACK_ADMIN_WEBHOOK_URL "Slack Admin Webhook URL (https://hooks.slack.com/...)" ""
prompt_var LMS_ADMIN_CHANNEL "Slack Admin Channel ID (e.g. C07ABCDEF12)" ""

# Google / Gemini
echo ""
info "── Google / Gemini Configuration ──"
prompt_var GEMINI_API_KEY "Gemini API Key" "" "true"
prompt_var GOOGLE_SHEETS_BACKUP_ID "Google Sheets Backup ID (from URL)" ""
prompt_var LESSONS_SHEET_ID "Lessons Sheet ID (from URL)" ""
prompt_var ASSIGNMENT_DRIVE_WEBHOOK_URL "Assignment Drive Webhook URL" ""

# n8n auth
echo ""
info "── n8n Admin Configuration ──"
prompt_var N8N_BASIC_AUTH_USER "n8n admin username" "admin"
prompt_var N8N_BASIC_AUTH_PASSWORD "n8n admin password (min 12 chars)" "" "true"

# Validate password length
while [[ ${#N8N_BASIC_AUTH_PASSWORD} -lt 12 ]]; do
  warn "Password must be at least 12 characters. Please try again."
  prompt_var N8N_BASIC_AUTH_PASSWORD "n8n admin password (min 12 chars)" "" "true"
done

# Auto-generate secrets if not set
if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
  POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
  ok "Auto-generated POSTGRES_PASSWORD"
fi

if [[ -z "${N8N_ENCRYPTION_KEY:-}" ]]; then
  N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
  ok "Auto-generated N8N_ENCRYPTION_KEY (32-char hex)"
fi

if [[ -z "${PUBLISH_SECRET:-}" ]]; then
  PUBLISH_SECRET=$(openssl rand -base64 32 | tr -d '/+=')
  ok "Auto-generated PUBLISH_SECRET"
fi

# Write all values back to .env
cat > .env <<EOF
# Generated by setup.sh on $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# DO NOT commit this file to version control.

DOMAIN=${DOMAIN}
SSL_EMAIL=${SSL_EMAIL}

N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
GENERIC_TIMEZONE=${GENERIC_TIMEZONE:-Pacific/Auckland}

N8N_HOST=${DOMAIN}
N8N_PORT=5678
N8N_PROTOCOL=https
WEBHOOK_URL=https://${DOMAIN}/

POSTGRES_USER=${POSTGRES_USER:-n8n}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB:-n8n}
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
DB_TYPE=postgresdb
DB_POSTGRESDB_DATABASE=${POSTGRES_DB:-n8n}
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_USER=${POSTGRES_USER:-n8n}
DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}

SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}
SLACK_SIGNING_SECRET=${SLACK_SIGNING_SECRET}
SLACK_ADMIN_WEBHOOK_URL=${SLACK_ADMIN_WEBHOOK_URL}
LMS_ADMIN_CHANNEL=${LMS_ADMIN_CHANNEL}

GEMINI_API_KEY=${GEMINI_API_KEY}
GOOGLE_SHEETS_BACKUP_ID=${GOOGLE_SHEETS_BACKUP_ID}
LESSONS_SHEET_ID=${LESSONS_SHEET_ID}
ASSIGNMENT_DRIVE_WEBHOOK_URL=${ASSIGNMENT_DRIVE_WEBHOOK_URL}

PUBLISH_SECRET=${PUBLISH_SECRET}

NOTION_SYNC_ENABLED=${NOTION_SYNC_ENABLED:-false}
NOTION_LESSONS_DB_ID=${NOTION_LESSONS_DB_ID:-565f1776-df27-461b-99e3-b70b2ee11dd2}
EOF

ok ".env written successfully"

# ─── Step 3: SSL Certificate ─────────────────────────────────────────────────
header "Step 3/10 — SSL certificate"

SSL_DIR="./nginx/ssl"
mkdir -p "$SSL_DIR"

if [[ -f "$SSL_DIR/fullchain.pem" ]] && [[ -f "$SSL_DIR/privkey.pem" ]]; then
  ok "SSL certificates already exist — skipping"
else
  info "Requesting Let's Encrypt certificate for $DOMAIN..."

  # Stop nginx if running (port 80 must be free for certbot standalone)
  docker compose stop nginx 2>/dev/null || true

  if docker run --rm \
    -p 80:80 \
    -v "$(pwd)/nginx/ssl:/etc/letsencrypt/live/${DOMAIN}" \
    certbot/certbot certonly \
      --standalone \
      --non-interactive \
      --agree-tos \
      --email "${SSL_EMAIL}" \
      --domain "${DOMAIN}" \
      --cert-path "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" \
      --key-path "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" \
    2>&1; then
    ok "Let's Encrypt certificate obtained"
  else
    warn "Let's Encrypt failed — generating self-signed certificate"
    warn "This is NOT suitable for production. Fix your DNS and re-run setup.sh."

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "$SSL_DIR/privkey.pem" \
      -out "$SSL_DIR/fullchain.pem" \
      -subj "/C=NZ/ST=Auckland/L=Auckland/O=RWR Group/CN=${DOMAIN}" \
      2>/dev/null

    ok "Self-signed certificate generated (development only)"
  fi
fi

# Patch nginx.conf with the actual domain
sed -i "s/\\\$DOMAIN/${DOMAIN}/g" ./nginx/nginx.conf 2>/dev/null || true

# ─── Step 4: Build and start ─────────────────────────────────────────────────
header "Step 4/10 — Build and start containers"

info "Building images and starting services..."
docker compose -f docker-compose.yml up -d --build

ok "Containers started"

# ─── Step 5: Wait for services ───────────────────────────────────────────────
header "Step 5/10 — Waiting for services to be ready"

wait_for_service() {
  local name="$1"
  local check_cmd="$2"
  local max_wait=120
  local elapsed=0

  info "Waiting for $name (max ${max_wait}s)..."
  while ! eval "$check_cmd" &>/dev/null; do
    if [[ $elapsed -ge $max_wait ]]; then
      err "$name did not become healthy within ${max_wait}s"
      err "Check logs: docker compose logs $name"
      exit 1
    fi
    sleep 3
    elapsed=$((elapsed + 3))
    echo -n "."
  done
  echo
  ok "$name is ready (${elapsed}s)"
}

wait_for_service "postgres" \
  "docker compose exec -T postgres pg_isready -U ${POSTGRES_USER:-n8n} -d ${POSTGRES_DB:-n8n}"

wait_for_service "n8n" \
  "curl -sf http://localhost:5678/healthz"

# Wait a bit more for n8n to finish internal setup
sleep 5

# ─── Step 6: Import workflows ────────────────────────────────────────────────
header "Step 6/10 — Importing workflows"

bash scripts/import-workflows.sh
ok "Workflow import complete"

# ─── Step 7: Patch workflow IDs ──────────────────────────────────────────────
header "Step 7/10 — Patching workflow IDs in supervisor router"

python3 scripts/update-workflow-ids.py
ok "Workflow ID patching complete"

# ─── Step 8: Activate all workflows ─────────────────────────────────────────
header "Step 8/10 — Activating workflows"

N8N_AUTH=$(echo -n "${N8N_BASIC_AUTH_USER}:${N8N_BASIC_AUTH_PASSWORD}" | base64)
N8N_API="http://localhost:5678/api/v1"

# Get all workflow IDs
WORKFLOW_IDS=$(curl -sf \
  -H "Authorization: Basic ${N8N_AUTH}" \
  "${N8N_API}/workflows" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ids = [str(w['id']) for w in data.get('data', [])]
print(' '.join(ids))
")

activated=0
failed=0
for wf_id in $WORKFLOW_IDS; do
  if curl -sf -X PATCH \
    -H "Authorization: Basic ${N8N_AUTH}" \
    -H "Content-Type: application/json" \
    -d '{"active": true}' \
    "${N8N_API}/workflows/${wf_id}" > /dev/null; then
    activated=$((activated + 1))
  else
    warn "Failed to activate workflow ID ${wf_id}"
    failed=$((failed + 1))
  fi
done

ok "Activated ${activated} workflow(s) (${failed} failed)"

# ─── Step 9: Health check ─────────────────────────────────────────────────────
header "Step 9/10 — Running health check"

bash scripts/health-check.sh || warn "Some health checks failed — see output above"

# ─── Step 10: Summary ────────────────────────────────────────────────────────
header "Step 10/10 — Setup complete!"

echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         RWR Group Slack LMS — Setup Complete! ✅             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BOLD}Access URLs:${NC}"
echo -e "  n8n Editor:     ${GREEN}https://${DOMAIN}/${NC}"
echo -e "  n8n Username:   ${N8N_BASIC_AUTH_USER}"
echo -e "  n8n Password:   (stored in .env)"

echo ""
echo -e "${BOLD}Webhook URLs for Slack Slash Commands:${NC}"
echo -e "  Supervisor:     ${GREEN}https://${DOMAIN}/webhook/supervisor${NC}"
echo -e "  Submit:         ${GREEN}https://${DOMAIN}/webhook/slack-interactions${NC}"
echo -e "  Backup:         ${GREEN}https://${DOMAIN}/webhook/backup${NC}"

echo ""
echo -e "${BOLD}Content Factory Webhooks:${NC}"
echo -e "  Lesson Edits:   ${GREEN}https://${DOMAIN}/webhook/lesson-edit-detect${NC}"
echo -e "  Publish:        ${GREEN}https://${DOMAIN}/webhook/publish-lesson${NC}"

echo ""
echo -e "${BOLD}Database:${NC}"
echo -e "  Host:     postgres (internal)"
echo -e "  Database: ${POSTGRES_DB:-n8n}"
echo -e "  User:     ${POSTGRES_USER:-n8n}"

echo ""
echo -e "${BOLD}PUBLISH_SECRET (for Agent 18 X-Publish-Token header):${NC}"
echo -e "  ${YELLOW}${PUBLISH_SECRET}${NC}"

echo ""
echo -e "${BOLD}Next Steps:${NC}"
echo -e "  1. Configure Slack slash commands (see README.md)"
echo -e "  2. Install Google Apps Script (scripts/google-apps-script/SheetEditDetector.js)"
echo -e "  3. Set script property: AGENT_16_WEBHOOK_URL = https://${DOMAIN}/webhook/lesson-edit-detect"
echo -e "  4. Configure Google Sheets OAuth2 credentials in n8n"
echo -e "  5. Run health check: ${YELLOW}./scripts/health-check.sh${NC}"

echo ""
ok "Setup finished. Your LMS is live at https://${DOMAIN}/"
