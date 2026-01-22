CREATE TABLE IF NOT EXISTS coach_chat (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  athlete_id TEXT NOT NULL,
  channel TEXT NOT NULL,
  role TEXT NOT NULL,
  message TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);

CREATE INDEX IF NOT EXISTS idx_coach_chat_athlete_time
  ON coach_chat(athlete_id, created_at);

CREATE TABLE IF NOT EXISTS athlete_feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  athlete_id TEXT NOT NULL,
  session_date TEXT,
  perceived TEXT,
  rpe INTEGER,
  conditions TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);

CREATE INDEX IF NOT EXISTS idx_feedback_athlete_time
  ON athlete_feedback(athlete_id, created_at);
