ALTER TABLE session_log ADD COLUMN activity_id TEXT;

CREATE INDEX IF NOT EXISTS idx_session_log_activity_id
  ON session_log(activity_id);
