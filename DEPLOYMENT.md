# RWR LMS — Hostinger VPS Deployment Guide

## A. What Was Broken (Root Causes)

### 1. PostgreSQL SSL crash (primary cause)
n8n's PostgreSQL driver (`pg`) attempts SSL connections by default. A local Docker
Postgres container has no SSL certificate configured, so the connection fails:

```
Error: SSL routines: SSL_read: EOF detected
```

n8n exits before ever serving `/healthz`, so the container is immediately unhealthy.

**Fix applied:** `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false` in `docker-compose.yml`

---

### 2. Healthcheck `start_period` too short (timing cause)
The custom entrypoint script flow on **first boot**:

| Step | Time |
|---|---|
| n8n internal startup (DB migration, init) | up to 120 s |
| Workflow import (18 files × ~1 s each) | ~36 s |
| **Total before `/healthz` is stable** | **up to 156 s** |

The old Docker grace window was: `60s start_period + 8 retries × 15s = 180s` — barely
enough, and any VPS slowness pushed it past the limit.

**Fix applied:** `start_period: 180s` and `retries: 12` → grace window is now 360 s.

---

### 3. Missing `N8N_ENCRYPTION_KEY` (crash if .env incomplete)
n8n refuses to start without an encryption key:

```
Error: Encryption key is not set. Please set the N8N_ENCRYPTION_KEY environment variable.
```

If `setup.sh` was not run to auto-generate this value, the container exits immediately.

**Fix:** Generate and set this value before deploying (see Section C).

---

### 4. `N8N_SECURE_COOKIE=false` missing (auth failure behind nginx)
When nginx terminates SSL and forwards HTTP to n8n internally, n8n's session cookies
carry the `Secure` flag. Browsers reject `Secure` cookies over HTTP, so the editor UI
login fails silently.

**Fix applied:** `N8N_SECURE_COOKIE=false` in `docker-compose.yml`

---

### 5. Entrypoint execute permissions
`COPY entrypoint.sh /entrypoint.sh` in the Dockerfile preserves source file permissions.
If the file is not committed with the execute bit set in git, the container fails:

```
exec /entrypoint.sh: permission denied
```

**Fix applied:** `RUN chmod +x /entrypoint.sh` added to `n8n/Dockerfile`

---

## B. Corrected Configuration Summary

### docker-compose.yml — key changes

```yaml
n8n:
  environment:
    # Auth (added)
    N8N_SECURE_COOKIE: "false"        # ← NEW: required behind nginx SSL
    N8N_LOG_LEVEL: info               # ← NEW: better startup diagnostics

    # Database (added)
    DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED: "false"  # ← NEW: fixes SSL crash

  healthcheck:
    interval: 15s
    timeout: 10s
    retries: 12         # was 8  — more buffer for slow VPS
    start_period: 180s  # was 60s — first-boot import takes up to 160s
```

### n8n/Dockerfile — key change

```dockerfile
# Ensure entrypoint is executable (git may not preserve +x bit)
USER root
RUN chmod +x /entrypoint.sh
USER node
```

---

## C. Required .env Setup

### Step 1 — Copy the template
```bash
cd /path/to/rwr-lms
cp .env.template .env
```

### Step 2 — Fill in required values
Edit `.env` and set every `[REQUIRED]` variable:

```bash
nano .env
```

| Variable | Example | Notes |
|---|---|---|
| `DOMAIN` | `lms.rwrgroup.com` | Must resolve to this VPS IP |
| `SSL_EMAIL` | `admin@rwrgroup.com` | Let's Encrypt notifications |
| `N8N_BASIC_AUTH_USER` | `admin` | Editor UI username |
| `N8N_BASIC_AUTH_PASSWORD` | `<strong-pw>` | Min 12 chars |
| `SLACK_BOT_TOKEN` | `xoxb-...` | From Slack App dashboard |
| `SLACK_SIGNING_SECRET` | `a1b2c3...` | 32-char hex |
| `SLACK_ADMIN_WEBHOOK_URL` | `https://hooks.slack.com/...` | Admin alert channel |
| `LMS_ADMIN_CHANNEL` | `C07ABCDEF12` | Channel ID (not name) |
| `GEMINI_API_KEY` | `AIza...` | From aistudio.google.com |
| `GOOGLE_SHEETS_BACKUP_ID` | `1BxiM...` | Backup sheet ID |
| `LESSONS_SHEET_ID` | `1RmhK...` | Lessons sheet ID |
| `ASSIGNMENT_DRIVE_WEBHOOK_URL` | `https://script.google.com/...` | Drive webhook |

### Step 3 — Generate secrets (run once, save outputs)
```bash
# PostgreSQL password
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" >> .env

# n8n encryption key — BACK THIS UP; losing it = unrecoverable credentials
echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)" >> .env

# Publish secret for Agent 18
echo "PUBLISH_SECRET=$(openssl rand -hex 24)" >> .env
```

> **Critical:** Back up `N8N_ENCRYPTION_KEY` in a password manager immediately.
> If this is lost, all credentials stored in n8n are permanently unrecoverable.

---

## D. Step-by-Step Hostinger VPS Deployment

### Prerequisites
- Hostinger VPS with Ubuntu 22.04 LTS
- Docker Engine 24+ and Docker Compose v2 installed
- Domain A record pointing to the VPS IP (required for Let's Encrypt)
- SSH access to the VPS

### Install Docker (if not already installed)
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

### Deploy

```bash
# 1. Clone the repository
git clone https://github.com/sallymayjob/lms.git /opt/rwr-lms
cd /opt/rwr-lms

# 2. Set up environment
cp .env.template .env
nano .env   # fill in all [REQUIRED] values (see Section C)

# 3. Generate secrets (if not using setup.sh)
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" >> .env
echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)" >> .env
echo "PUBLISH_SECRET=$(openssl rand -hex 24)" >> .env

# 4. Obtain SSL certificate (requires domain DNS to already resolve)
sudo apt-get install -y certbot
source .env
sudo certbot certonly --standalone \
  --non-interactive --agree-tos \
  --email "$SSL_EMAIL" \
  -d "$DOMAIN"

# Copy certs to nginx ssl directory
mkdir -p nginx/ssl
sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem nginx/ssl/
sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem nginx/ssl/
sudo chmod 644 nginx/ssl/*.pem

# Update nginx.conf with your actual domain
sed -i "s/\$DOMAIN/$DOMAIN/g" nginx/nginx.conf

# 5. Build and start
docker compose -f docker-compose.yml build
docker compose -f docker-compose.yml up -d

# 6. Watch startup (first boot takes 3-5 minutes for workflow import)
docker compose logs -f n8n

# 7. Verify all containers are healthy
docker compose ps
```

Expected output after ~5 minutes:
```
NAME               STATUS                  PORTS
rwr-lms-postgres   Up X minutes (healthy)
rwr-lms-n8n        Up X minutes (healthy)
rwr-lms-nginx      Up X minutes            0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
```

### Post-deployment
```bash
# Run the full health check
./scripts/health-check.sh

# Configure Slack slash commands to point to:
# https://<DOMAIN>/webhook/supervisor
```

---

## E. Safe Rebuild Commands (No Data Loss)

Docker named volumes (`postgres_data`, `n8n_data`) are **not removed** by any of
these commands. Your database and n8n credentials are always preserved.

### Rebuild only the n8n image (most common — after code changes)
```bash
docker compose -f docker-compose.yml build --no-cache n8n
docker compose -f docker-compose.yml up -d n8n
```

### Full restart (no rebuild — just restart containers)
```bash
docker compose -f docker-compose.yml restart
```

### Full tear-down and redeploy (volumes preserved)
```bash
# Stop and remove containers, networks (NOT volumes)
docker compose -f docker-compose.yml down

# Redeploy
docker compose -f docker-compose.yml up -d --build
```

### Nuclear reset (DESTROYS ALL DATA — use only on fresh setup)
```bash
# WARNING: This deletes postgres_data and n8n_data volumes permanently
docker compose -f docker-compose.yml down -v
docker compose -f docker-compose.yml up -d --build
```

### Update to latest n8n image
```bash
# Pull latest n8n base image
docker pull n8nio/n8n:latest

# Rebuild your custom image and restart
docker compose -f docker-compose.yml build --no-cache n8n
docker compose -f docker-compose.yml up -d n8n
```

---

## Troubleshooting

### n8n still unhealthy after fixes
```bash
# Check for error messages during startup
docker logs rwr-lms-n8n --tail 100

# Verify environment variables are loaded
docker compose -f docker-compose.yml config | grep -A 5 'n8n_encryption'

# Check postgres is accepting connections
docker exec rwr-lms-postgres pg_isready -U n8n -d n8n
```

### Common errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `SSL SYSCALL error: EOF detected` | Missing `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED` | Already fixed in this commit |
| `Encryption key is not set` | Empty `N8N_ENCRYPTION_KEY` in .env | Generate key (Section C Step 3) |
| `exec /entrypoint.sh: permission denied` | Missing execute bit | Already fixed in Dockerfile |
| `container is unhealthy` after 3 min | Timeout still too short | Check `docker logs rwr-lms-n8n` for the actual crash |
| n8n editor redirects to HTTP | Missing `N8N_SECURE_COOKIE=false` | Already fixed in this commit |

### Certificate renewal (set up cron)
```bash
# Add to crontab (crontab -e)
0 3 * * * certbot renew --quiet && \
  cp /etc/letsencrypt/live/YOURDOMAIN/fullchain.pem /opt/rwr-lms/nginx/ssl/ && \
  cp /etc/letsencrypt/live/YOURDOMAIN/privkey.pem /opt/rwr-lms/nginx/ssl/ && \
  docker compose -f /opt/rwr-lms/docker-compose.yml restart nginx
```
