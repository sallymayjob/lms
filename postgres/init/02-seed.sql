-- ═══════════════════════════════════════════════════════════════════════════
-- RWR Group Slack LMS — Seed Data
-- File: 02-seed.sql
-- ═══════════════════════════════════════════════════════════════════════════
-- Sample courses and modules for testing after initial deployment.
-- This data does NOT include real lesson content — it is for system testing only.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Sample Courses ──────────────────────────────────────────────────────────
INSERT INTO courses (code, title, description)
VALUES
  (
    'M01-COURSE',
    'Month 1: Recruiting Foundations',
    'Core recruiting skills for professionals new to talent acquisition. Guided difficulty.'
  ),
  (
    'M02-COURSE',
    'Month 2: Sourcing Mastery',
    'Advanced sourcing techniques using LinkedIn, ATS, and Boolean search. Guided difficulty.'
  ),
  'M03-COURSE',
    'Month 3: Candidate Experience',
    'Building exceptional candidate pipelines and communication workflows. Guided difficulty.'
  )
ON CONFLICT (code) DO NOTHING;

-- ─── Sample Modules (Lessons) ─────────────────────────────────────────────────
-- Month 1 Week 1
INSERT INTO modules (course_id, title, content, position)
VALUES
  (
    (SELECT id FROM courses WHERE code = 'M01-COURSE'),
    'Week 1, Lesson 1: What Recruiting Professionals Actually Do',
    E'Welcome to the RWR Group LMS.\n\nThis is your first lesson. Complete the mission below and submit using the /submit command.\n\n*Mission:* Write a 3-sentence definition of a recruiting professional''s role that you could use to explain your job to a non-recruiter friend.\n\n*Submit:* /submit M01-W01-L01 complete',
    1
  ),
  (
    (SELECT id FROM courses WHERE code = 'M01-COURSE'),
    'Week 1, Lesson 2: Reading a Job Brief Like a Pro',
    E'In this lesson you''ll learn to extract the hidden requirements from any job brief.\n\n*Mission:* Take a real job brief from your current role and list the 3 unstated requirements the hiring manager will actually use to screen candidates.\n\n*Submit:* /submit M01-W01-L02 complete',
    2
  ),
  (
    (SELECT id FROM courses WHERE code = 'M01-COURSE'),
    'Week 1, Lesson 3: Your ATS is Not a Database',
    E'Most recruiting professionals use their ATS as a filing cabinet. This lesson reframes it as a talent intelligence system.\n\n*Mission:* Log into your ATS and run a search for a role you''ve filled in the past 6 months. Find one qualified candidate who was rejected and document why.\n\n*Submit:* /submit M01-W01-L03 complete',
    3
  )
ON CONFLICT (course_id, position) DO NOTHING;

-- ─── Sample Lesson in lessons table (for Content Factory testing) ─────────────
INSERT INTO lessons (
  lesson_id, month, week, lesson_num,
  type, difficulty, tone,
  hook, core_content, insight, takeaway,
  mission_description, mission_minutes, mission_format, mission_tools, alternative_path,
  verification, expected_evidence, submit_command,
  slack_formatted,
  qa_score, qa_verdict, qa_run_date,
  publication_status
)
VALUES (
  'M01-W01-L01', 1, 1, 1,
  'foundational', 'guided', 'direct',
  'You chose recruiting because you wanted to help people. But the job is actually about making hiring managers'' lives easier — not candidates'' lives.',
  E'Recruiting professionals operate at the intersection of business strategy and human behaviour. Your primary client is the hiring manager, not the candidate. Understanding this reframes every conversation you have.\n\nWhen a hiring manager says "I need someone who just gets it" — that is a business problem, not a personality request. Translating vague requirements into specific, measurable criteria is the core skill that separates average recruiters from professionals.',
  'The best recruiting professionals spend 80% of their intake meeting challenging the job brief — not taking notes on it.',
  'Your job is to make the hiring decision easier, not to find the perfect candidate.',
  'Write a 3-sentence definition of a recruiting professional''s role that you could explain to a friend outside the industry. Focus on the business outcome you create, not the tasks you perform.',
  5, 'text', 'Any text editor or notepad',
  'If you struggle with "business outcome" framing, write it from the hiring manager''s perspective instead: what problem do they wake up with that you solve?',
  'Could you answer this question by Googling it, or does it require you to actually think about your own experience?',
  'A 3-sentence statement that describes recruiting impact in business terms (not task terms)',
  '/submit M01-W01-L01 complete',
  E'*Lesson M01-W01-L01: What Recruiting Professionals Actually Do*\n\n> You chose recruiting because you wanted to help people. But the job is actually about making hiring managers'' lives easier — not candidates'' lives.\n\n*Core lesson:*\nRecruiting professionals operate at the intersection of business strategy and human behaviour. Your primary client is the hiring manager, not the candidate.\n\n*Insight:* The best recruiting professionals spend 80% of their intake meeting challenging the job brief — not taking notes on it.\n\n*Takeaway:* Your job is to make the hiring decision easier, not to find the perfect candidate.\n\n*Mission (5 min):* Write a 3-sentence definition of a recruiting professional''s role that you could explain to a friend outside the industry.\n\nWhen done: `/submit M01-W01-L01 complete`',
  92.5, 'STRONG_PASS', CURRENT_DATE,
  'PUBLISHED'
)
ON CONFLICT (lesson_id) DO NOTHING;
