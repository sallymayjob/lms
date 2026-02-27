-- ═══════════════════════════════════════════════════════════════════════════
-- RWR Group Slack LMS — Performance Indexes
-- File: 03-indexes.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Delivery layer indexes ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_slack_user_id
  ON users(slack_user_id);

CREATE INDEX IF NOT EXISTS idx_users_slack_team_id
  ON users(slack_team_id);

CREATE INDEX IF NOT EXISTS idx_enrolments_user_id
  ON enrolments(user_id);

CREATE INDEX IF NOT EXISTS idx_enrolments_course_id
  ON enrolments(course_id);

CREATE INDEX IF NOT EXISTS idx_enrolments_current_module_id
  ON enrolments(current_module_id);

CREATE INDEX IF NOT EXISTS idx_progress_user_id
  ON progress(user_id);

CREATE INDEX IF NOT EXISTS idx_progress_module_id
  ON progress(module_id);

CREATE INDEX IF NOT EXISTS idx_certificates_user_id
  ON certificates(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON notifications(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_sent_at
  ON notifications(sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_nudge_reactions_user_id
  ON nudge_reactions(user_id);

CREATE INDEX IF NOT EXISTS idx_nudge_reactions_lesson_id
  ON nudge_reactions(lesson_id);

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_user_id
  ON assignment_submissions(user_id);

CREATE INDEX IF NOT EXISTS idx_assignment_submissions_lesson_id
  ON assignment_submissions(lesson_id);

-- ─── Content factory indexes ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_lessons_lesson_id
  ON lessons(lesson_id);

CREATE INDEX IF NOT EXISTS idx_lessons_publication_status
  ON lessons(publication_status);

CREATE INDEX IF NOT EXISTS idx_lessons_month_week
  ON lessons(month, week);

CREATE INDEX IF NOT EXISTS idx_lessons_qa_verdict
  ON lessons(qa_verdict);

CREATE INDEX IF NOT EXISTS idx_qa_log_lesson_id
  ON qa_log(lesson_id);

CREATE INDEX IF NOT EXISTS idx_qa_log_run_date
  ON qa_log(run_date DESC);

CREATE INDEX IF NOT EXISTS idx_qa_log_golden_example
  ON qa_log(golden_example) WHERE golden_example = true;

CREATE INDEX IF NOT EXISTS idx_pipeline_status_lesson_id
  ON pipeline_status(lesson_id);

CREATE INDEX IF NOT EXISTS idx_pipeline_status_publication_status
  ON pipeline_status(publication_status);
