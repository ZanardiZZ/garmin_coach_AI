CREATE TABLE IF NOT EXISTS config_kv (
  key TEXT PRIMARY KEY,
  value_enc TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT
);
