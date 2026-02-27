#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# RWR Group Slack LMS — Daily PostgreSQL Backup Script
# ═══════════════════════════════════════════════════════════════════════════
# Usage: ./postgres/backup/pg-backup.sh
# Recommended: Add to crontab — 0 2 * * * /path/to/rwr-lms/postgres/backup/pg-backup.sh
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load .env
if [[ -f "${PROJECT_DIR}/.env" ]]; then
  set -o allexport
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/.env"
  set +o allexport
fi

POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
BACKUP_DIR="${PROJECT_DIR}/postgres/backup/dumps"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/rwr_lms_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo -e "${GREEN}RWR LMS — PostgreSQL Backup${NC}"
echo -e "Timestamp: $(date -u)"

# ─── Create backup ────────────────────────────────────────────────────────────
echo "Creating backup: $BACKUP_FILE"

if docker compose -f "${PROJECT_DIR}/docker-compose.yml" exec -T postgres \
  pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" | gzip > "${BACKUP_FILE}"; then

  SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
  echo -e "${GREEN}✓ Backup created (${SIZE})${NC}"
else
  echo -e "${RED}✗ Backup failed${NC}" >&2
  exit 1
fi

# ─── Remove old backups ───────────────────────────────────────────────────────
echo "Removing backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_DIR" -name "rwr_lms_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete
echo -e "${GREEN}✓ Old backups cleaned${NC}"

# ─── List current backups ─────────────────────────────────────────────────────
echo ""
echo "Current backups:"
ls -lh "${BACKUP_DIR}"/*.sql.gz 2>/dev/null || echo "  (none)"

echo ""
echo -e "${GREEN}Backup complete.${NC}"
