# RWR Group Slack LMS

A fully automated, Docker-based Learning Management System for Slack — built on n8n, PostgreSQL, and Nginx.

---

## Prerequisites

Before running setup, ensure the following are in place:

| Requirement | Notes |
|---|---|
| **Hostinger VPS** — Ubuntu 22.04 LTS, min 2GB RAM | 4GB recommended for AI workloads |
| **Docker Engine 24+** | [Install Docker](https://docs.docker.com/engine/install/ubuntu/) |
| **Docker Compose v2** | Included with Docker Engine 24+ |
| **Domain name** | A-record must point to your VPS IP before running setup |
| **Slack App** | With Bot Token, Signing Secret, and Incoming Webhook |
| **Google Gemini API key** | From [Google AI Studio](https://aistudio.google.com/app/apikey) |
| **Google Sheets** | Two docs — one for LMS backup, one for lesson content |

---

## Quick Start (3 Steps)

```bash
# 1. Clone the repo onto your VPS
git clone https://github.com/your-org/rwr-lms.git && cd rwr-lms

# 2. Copy your existing n8n workflow exports into place
# (Skip if you only need Agents 16-18 — those are already included)
cp /path/to/your/n8n-exports/*.json n8n/workflows/

# 3. Run the one-command setup
chmod +x setup.sh && ./setup.sh
```

`setup.sh` handles everything: SSL certificate, Docker build, workflow import, and activation.

---

## What setup.sh Does

1. Pre-flight checks (Docker, curl, openssl)
2. Interactive environment variable collection
3. Let's Encrypt SSL certificate (falls back to self-signed if DNS is not ready)
4. Docker image build and container start
5. Health polling until Postgres and n8n are ready
6. Workflow import in dependency order (18 workflows)
7. Workflow ID patching (supervisor-router executeWorkflow references)
8. Workflow activation via n8n REST API
9. Health check report
10. Summary with all URLs and webhook paths

---

## Slack App Configuration

In your Slack App settings, configure **Slash Commands** to point to your domain:

| Slash Command | Request URL |
|---|---|
| `/enroll` | `https://DOMAIN/webhook/supervisor` |
| `/tutor` | `https://DOMAIN/webhook/supervisor` |
| `/progress` | `https://DOMAIN/webhook/supervisor` |
| `/catalog` | `https://DOMAIN/webhook/supervisor` |
| `/help` | `https://DOMAIN/webhook/supervisor` |
| `/certify` | `https://DOMAIN/webhook/supervisor` |
| `/unenroll` | `https://DOMAIN/webhook/supervisor` |
| `/report` | `https://DOMAIN/webhook/supervisor` |
| `/gaps` | `https://DOMAIN/webhook/supervisor` |
| `/backup` | `https://DOMAIN/webhook/backup` |
| `/submit` | `https://DOMAIN/webhook/slack-interactions` |

Also configure under **Interactivity and Shortcuts**:
- Request URL: `https://DOMAIN/webhook/slack-interactions`

Under **Event Subscriptions** (if using reaction-based nudge confirmation):
- Request URL: `https://DOMAIN/webhook/slack-interactions`

---

## Google Sheets Setup

### Backup Sheet (`GOOGLE_SHEETS_BACKUP_ID`)

Required tabs (Agent 14 writes to these nightly):

| Tab Name | Purpose |
|---|---|
| `Progress` | User module completion records |
| `Enrollments` | Active and completed enrollments |
| `Certificates` | Issued completion certificates |
| `Snapshot` | Full system snapshot |

### Lessons Sheet (`LESSONS_SHEET_ID`)

Required tabs:

| Tab Name | Purpose |
|---|---|
| `Lessons` | Lesson content source of truth (columns match `lessons` table schema) |
| `QA_Log` | Historical QA run results |
| `Pipeline_Status` | Per-lesson pipeline state |
| `Checksums` | Created automatically by SheetEditDetector.js |

**Lessons tab column headers** (Row 1, match exactly):

```
lesson_id | month | week | lesson_num | type | difficulty | tone | hook | core_content |
insight | takeaway | mission_description | mission_minutes | mission_format |
mission_tools | alternative_path | verification | expected_evidence | submit_command |
slack_formatted | media_required | media_brief_type | qa_score | qa_verdict |
qa_run_date | priority | revision_count | publication_status | last_edited_by |
last_edited_at | notion_page_id
```

---

## Google Apps Script Installation

1. Open your **Lessons Google Sheet**
2. Go to **Extensions > Apps Script**
3. Replace all content with `scripts/google-apps-script/SheetEditDetector.js`
4. Set the webhook URL in Script Properties:
   - Go to **File > Project Properties > Script Properties**
   - Add key: `AGENT_16_WEBHOOK_URL`
   - Value: `https://YOUR_DOMAIN/webhook/lesson-edit-detect`
5. From the **Run** menu, run `setupTriggers` (authorize when prompted)
6. Run `testWebhook` to verify connectivity

The script fires automatically on any cell edit in the Lessons tab, computes an MD5 checksum of the row, and posts to Agent 16 only when the content has actually changed.

---

## n8n Credentials Setup

After `setup.sh` completes, configure these credentials in the n8n UI:

### 1. PostgreSQL
- Go to **Credentials > New > Postgres**
- Use values from credential template: `n8n/credentials-template/postgres.json`
- Name it exactly: `RWR LMS Postgres`
- Host: `postgres`, Port: `5432`, User/Pass from `.env`

### 2. Google Sheets OAuth2
- Go to **Credentials > New > Google Sheets OAuth2 API**
- Set up OAuth2 in [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
- Add redirect URI: `https://YOUR_DOMAIN/rest/oauth2-credential/callback`
- Name it: `RWR LMS Google Sheets`

### 3. Gemini
- Gemini is called directly via HTTP Request nodes using `$env.GEMINI_API_KEY`
- No n8n credential needed — ensure `GEMINI_API_KEY` is set in `.env`

---

## Publishing a Lesson (Agent 18)

To publish an approved lesson to the LMS:

```bash
curl -X POST https://YOUR_DOMAIN/webhook/publish-lesson \
  -H "Content-Type: application/json" \
  -H "X-Publish-Token: YOUR_PUBLISH_SECRET" \
  -d '{"lesson_id": "M01-W01-L03"}'
```

The lesson must be in `APPROVED` status in the `lessons` table. Agent 18 will:
1. Validate the publish token
2. Create or update the course and module in the LMS
3. Optionally sync metadata to Notion
4. Mark the lesson `PUBLISHED`
5. Post a confirmation to the Slack admin channel

---

## Updating Workflows

After modifying a workflow JSON file:

```bash
# Re-import the updated workflow
docker compose exec n8n n8n import:workflow \
  --input=/home/node/workflows/agent-XX.json

# Re-activate the workflow
N8N_AUTH=$(echo -n "admin:YOUR_PASSWORD" | base64)
curl -X PATCH https://YOUR_DOMAIN/api/v1/workflows/WORKFLOW_ID \
  -H "Authorization: Basic ${N8N_AUTH}" \
  -H "Content-Type: application/json" \
  -d '{"active": true}'
```

---

## Monitoring and Maintenance

```bash
# Full health check
./scripts/health-check.sh

# Quick uptime check (suitable for cron)
./monitoring/uptime-check.sh

# Manual database backup
./postgres/backup/pg-backup.sh

# View live n8n logs
docker compose logs -f n8n

# View Postgres logs
docker compose logs -f postgres

# View Nginx access logs
docker compose logs -f nginx

# Restart all services
docker compose restart

# Stop all services
docker compose down
```

### Recommended Cron Jobs

```
# Daily DB backup at 2am
0 2 * * * /path/to/rwr-lms/postgres/backup/pg-backup.sh >> /var/log/rwr-lms-backup.log 2>&1

# Every 5 minutes uptime check
*/5 * * * * /path/to/rwr-lms/monitoring/uptime-check.sh >> /var/log/rwr-lms-uptime.log 2>&1
```

---

## Workflow Architecture

```
Slack User
    |
    v
/slash-command -> Nginx -> n8n Webhook
                              |
                              v
                    Agent 01: Supervisor Router
                    (routes by intent keyword)
                              |
          +-----------+-------+-----------+
          |           |                   |
          v           v                   v
    Agent 02: Quiz  Agent 03: Tutor  Agent 05: Catalog
    Agent 04: Progress  Agent 06: Help  Agent 07: Cert
    Agent 08: Enroll  Agent 09: Gaps  Agent 10: Unenroll
    Agent 11: Nudge  Agent 12: Report  Agent 13: Onboard
    Agent 14: Backup  Agent 15: Submit

Content Factory:
Google Sheets --edit--> Agent 16: Edit Detector --> Agent 17: Gemini Re-Tester
                                                          |
                         Agent 18: Publisher <------------+
                              |
                              v
                         LMS modules table
```

---

## Environment Variables Reference

See `.env.template` for full documentation. Key variables:

| Variable | Required | Description |
|---|---|---|
| `DOMAIN` | Yes | Your VPS domain (e.g. `lms.example.com`) |
| `SLACK_BOT_TOKEN` | Yes | `xoxb-...` token from Slack App |
| `SLACK_SIGNING_SECRET` | Yes | 32-char hex from Slack App |
| `GEMINI_API_KEY` | Yes | Google Gemini API key |
| `N8N_ENCRYPTION_KEY` | Auto | 32-char hex — back this up |
| `POSTGRES_PASSWORD` | Auto | Auto-generated strong password |
| `PUBLISH_SECRET` | Auto | Token for Agent 18 webhook |

---

## Troubleshooting

**n8n will not start:**
```bash
docker compose logs n8n
# Common causes: wrong Postgres password, or Postgres not ready yet
```

**Workflows not activating:**
```bash
# Check n8n API is reachable
curl http://localhost:5678/healthz

# List all workflows
N8N_AUTH=$(echo -n "admin:PASSWORD" | base64)
curl -H "Authorization: Basic ${N8N_AUTH}" http://localhost:5678/api/v1/workflows
```

**SSL certificate fails:**
```bash
# Ensure port 80 is open and DNS resolves to this server
curl -I http://your-domain.com
# Re-run setup.sh after fixing DNS
```

**Supervisor router routes to wrong agent:**
```bash
# Diagnose ID mismatches
python3 scripts/update-workflow-ids.py --dry-run

# Apply patches
python3 scripts/update-workflow-ids.py
```

**Google Apps Script not triggering:**
- Confirm `setupTriggers()` was run and authorized
- Check execution logs: View > Logs in Apps Script editor
- Verify `AGENT_16_WEBHOOK_URL` is set in Script Properties
- Run `testWebhook()` to test connectivity directly
