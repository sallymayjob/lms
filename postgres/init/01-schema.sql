-- ═══════════════════════════════════════════════════════════════════════════
-- RWR Group Slack LMS — PostgreSQL Schema
-- File: 01-schema.sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Executed automatically by Postgres on first container start.
-- Run order: 01-schema.sql → 02-seed.sql → 03-indexes.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- Enable pgcrypto for UUID generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─── Shared updated_at trigger ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ═══════════════════════════════════════════════════════════════════════════
-- DELIVERY LAYER TABLES (Agents 02–15)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── users ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id             SERIAL PRIMARY KEY,
  slack_user_id  VARCHAR(50)  UNIQUE NOT NULL,
  slack_team_id  VARCHAR(50),
  display_name   VARCHAR(255),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─── courses ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS courses (
  id          SERIAL PRIMARY KEY,
  code        VARCHAR(50)  UNIQUE NOT NULL,
  title       VARCHAR(255) NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── modules ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS modules (
  id         SERIAL PRIMARY KEY,
  course_id  INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title      VARCHAR(255) NOT NULL,
  content    TEXT,
  position   INT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (course_id, position)
);

-- ─── enrolments ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enrolments (
  id                SERIAL PRIMARY KEY,
  user_id           INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  course_id         INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  current_module_id INT REFERENCES modules(id) ON DELETE SET NULL,
  enrolled_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at      TIMESTAMPTZ,
  UNIQUE (user_id, course_id)
);

-- ─── progress ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS progress (
  id           SERIAL PRIMARY KEY,
  user_id      INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  module_id    INT NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, module_id)
);

-- ─── certificates ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS certificates (
  id        SERIAL PRIMARY KEY,
  user_id   INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  course_id INT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, course_id)
);

-- ─── notifications ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id                SERIAL PRIMARY KEY,
  user_id           INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  notification_type VARCHAR(50),
  message           TEXT,
  sent_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── nudge_reactions ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nudge_reactions (
  id            SERIAL PRIMARY KEY,
  user_id       INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lesson_id     VARCHAR(100),
  reaction_type VARCHAR(50),
  payload       JSONB,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── assignment_submissions ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS assignment_submissions (
  id              SERIAL PRIMARY KEY,
  user_id         INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lesson_id       VARCHAR(100),
  course_title    TEXT,
  assignment_link TEXT,
  screenshot_url  TEXT,
  drive_filename  TEXT,
  payload         JSONB,
  submitted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTENT FACTORY TABLES (Agents 16–18)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── lessons ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS lessons (
  id                    SERIAL PRIMARY KEY,
  lesson_id             VARCHAR(20) UNIQUE NOT NULL,  -- e.g. M03-W02-L04
  month                 INT,
  week                  INT,
  lesson_num            INT,

  -- ULC Components
  type                  VARCHAR(30),
  difficulty            VARCHAR(20),
  tone                  VARCHAR(20),
  hook                  TEXT,
  core_content          TEXT,
  insight               TEXT,
  takeaway              TEXT,

  -- Mission
  mission_description   TEXT,
  mission_minutes       INT,
  mission_format        VARCHAR(20),
  mission_tools         TEXT,
  alternative_path      TEXT,

  -- Verification & Submission
  verification          TEXT,
  expected_evidence     TEXT,
  submit_command        VARCHAR(50),

  -- Slack delivery
  slack_formatted       TEXT,

  -- Media
  media_required        BOOLEAN NOT NULL DEFAULT false,
  media_brief_type      VARCHAR(30),

  -- QA results
  qa_score              DECIMAL(5, 2),
  qa_verdict            VARCHAR(30),
  qa_run_date           DATE,
  priority              VARCHAR(5),
  revision_count        INT NOT NULL DEFAULT 0,

  -- Pipeline
  publication_status    VARCHAR(30) NOT NULL DEFAULT 'DRAFT',

  -- Audit
  last_edited_by        VARCHAR(100),
  last_edited_at        TIMESTAMPTZ,
  notion_page_id        VARCHAR(100),
  sheets_row_checksum   VARCHAR(64),

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_lessons_updated_at
  BEFORE UPDATE ON lessons
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─── qa_log ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS qa_log (
  id                    SERIAL PRIMARY KEY,
  log_id                UUID NOT NULL DEFAULT gen_random_uuid(),
  lesson_id             VARCHAR(20) NOT NULL,
  run_date              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  run_trigger           VARCHAR(30),    -- 'edit_retest', 'manual', 'scheduled'
  run_by                VARCHAR(100),

  -- Scores
  qa_score              DECIMAL(5, 2),
  qa_verdict            VARCHAR(30),

  -- Criterion scores
  c1_ulc                INT,
  c2_words              INT,
  c3_brand              INT,
  c4_mission            INT,
  c5_content            INT,
  c6_continuity         INT,

  -- Flags
  hard_fail_triggered   BOOLEAN NOT NULL DEFAULT false,
  override_reason       TEXT,
  golden_example        BOOLEAN NOT NULL DEFAULT false,

  -- Revision guidance
  revision_prompt       TEXT,
  target_agent          VARCHAR(50),

  -- Carry-forward PED flags
  ped_flags_carried     JSONB
);

-- ─── pipeline_status ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pipeline_status (
  id                    SERIAL PRIMARY KEY,
  lesson_id             VARCHAR(20) UNIQUE,
  pipeline_mode         VARCHAR(30),
  current_step          INT,
  started_at            TIMESTAMPTZ,
  revision_loop_count   INT NOT NULL DEFAULT 0,
  step_data             JSONB,
  soft_fails_logged     JSONB,
  publication_status    VARCHAR(30),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_pipeline_status_updated_at
  BEFORE UPDATE ON pipeline_status
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
