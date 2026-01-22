CREATE TABLE IF NOT EXISTS daily_metrics (
  athlete_id TEXT NOT NULL,
  day_date TEXT NOT NULL,
  total_distance_km REAL DEFAULT 0,
  total_time_min REAL DEFAULT 0,
  total_trimp REAL DEFAULT 0,
  total_elev_gain_m REAL DEFAULT 0,
  count_sessions INTEGER DEFAULT 0,
  count_easy INTEGER DEFAULT 0,
  count_quality INTEGER DEFAULT 0,
  count_long INTEGER DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (athlete_id, day_date),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);

CREATE INDEX IF NOT EXISTS idx_daily_metrics_athlete_day
  ON daily_metrics(athlete_id, day_date);
