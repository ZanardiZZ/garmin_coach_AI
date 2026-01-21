-- Ultra Coach - Schema SQL Centralizado
-- Versao: 1.0.0
-- Data: 2026-01-17
--
-- Este arquivo define todas as tabelas do sistema.
-- Execute com: sqlite3 coach.sqlite < schema.sql
-- Ou use: bin/init_db.sh

-- ============================================
-- TABELA: athlete_profile
-- Perfil do atleta com dados fisiologicos
-- ============================================
CREATE TABLE IF NOT EXISTS athlete_profile (
  athlete_id TEXT PRIMARY KEY,
  name TEXT,
  hr_max INTEGER NOT NULL,
  hr_rest INTEGER NOT NULL DEFAULT 50,
  goal_event TEXT,           -- ex: "Ultra 12h", "90km trail"
  weekly_hours_target REAL,  -- horas/semana alvo
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT
);

-- ============================================
-- TABELA: config_kv
-- Configuracoes (valores criptografados)
-- ============================================
CREATE TABLE IF NOT EXISTS config_kv (
  key TEXT PRIMARY KEY,
  value_enc TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT
);

-- ============================================
-- TABELA: coach_policy
-- Politicas de treino por modo (conservative, moderate, aggressive)
-- ============================================
CREATE TABLE IF NOT EXISTS coach_policy (
  mode TEXT PRIMARY KEY,     -- conservative, moderate, aggressive
  readiness_floor INTEGER NOT NULL DEFAULT 60,  -- minimo readiness para quality
  fatigue_cap INTEGER NOT NULL DEFAULT 70,      -- maximo fatigue permitido
  max_hard_days_week INTEGER NOT NULL DEFAULT 2,
  max_long_days_week INTEGER NOT NULL DEFAULT 1,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT
);

-- Politicas padrao
INSERT OR IGNORE INTO coach_policy (mode, readiness_floor, fatigue_cap, max_hard_days_week, max_long_days_week, notes)
VALUES
  ('conservative', 70, 60, 1, 1, 'Modo conservador para iniciantes ou recuperacao'),
  ('moderate', 60, 70, 2, 1, 'Modo moderado para atletas intermediarios'),
  ('aggressive', 50, 80, 2, 2, 'Modo agressivo para atletas experientes');

-- ============================================
-- TABELA: athlete_state
-- Estado atual do atleta (recalculado diariamente)
-- ============================================
CREATE TABLE IF NOT EXISTS athlete_state (
  athlete_id TEXT PRIMARY KEY,
  readiness_score REAL,      -- 0-100 (alto = pronto para treinar)
  fatigue_score REAL,        -- 0-100 (alto = cansado)
  monotony REAL,             -- variacao de carga (alto = ruim)
  strain REAL,               -- carga x monotonia
  weekly_load REAL,          -- TRIMP acumulado ultimos 7 dias
  weekly_distance_km REAL,
  weekly_time_min REAL,
  last_long_run_km REAL,
  last_long_run_at TEXT,
  last_quality_at TEXT,
  coach_mode TEXT NOT NULL DEFAULT 'moderate',  -- conservative, moderate, aggressive
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id),
  FOREIGN KEY (coach_mode) REFERENCES coach_policy(mode)
);

-- ============================================
-- TABELA: weekly_state
-- Resumo semanal para controle de volume
-- ============================================
CREATE TABLE IF NOT EXISTS weekly_state (
  athlete_id TEXT NOT NULL,
  week_start TEXT NOT NULL,  -- data da segunda-feira (YYYY-MM-DD)
  quality_days INTEGER DEFAULT 0,
  long_days INTEGER DEFAULT 0,
  total_time_min REAL DEFAULT 0,
  total_load REAL DEFAULT 0,
  total_distance_km REAL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (athlete_id, week_start),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);

-- ============================================
-- TABELA: session_log
-- Historico de treinos/atividades (importado do Garmin/Influx)
-- ============================================
CREATE TABLE IF NOT EXISTS session_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  athlete_id TEXT NOT NULL,
  start_at TEXT NOT NULL,    -- datetime local
  duration_min REAL,
  distance_km REAL,
  avg_hr INTEGER,
  max_hr INTEGER,
  avg_pace_min_km REAL,
  trimp REAL,                -- Training Impulse (carga)
  tags TEXT,                 -- comma-separated: easy,long,quality,import_influx
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(athlete_id, start_at),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);

CREATE INDEX IF NOT EXISTS idx_session_log_athlete_date
  ON session_log(athlete_id, start_at);

-- ============================================
-- TABELA: body_comp_log
-- Historico de composicao corporal (importado da balanca Index S2)
-- ============================================
CREATE TABLE IF NOT EXISTS body_comp_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  athlete_id TEXT NOT NULL,
  measured_at TEXT NOT NULL, -- datetime local
  device TEXT,               -- ex: "Index S2"
  bmi REAL,
  body_fat_pct REAL,
  body_water_pct REAL,
  bone_mass_kg REAL,
  muscle_mass_kg REAL,
  weight_kg REAL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT,
  UNIQUE(athlete_id, measured_at),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);

CREATE INDEX IF NOT EXISTS idx_body_comp_athlete_date
  ON body_comp_log(athlete_id, measured_at);

-- ============================================
-- TABELA: daily_plan
-- Plano diario deterministico (tipo de treino baseado em regras)
-- ============================================
CREATE TABLE IF NOT EXISTS daily_plan (
  athlete_id TEXT NOT NULL,
  plan_date TEXT NOT NULL,   -- YYYY-MM-DD
  workout_type TEXT NOT NULL, -- recovery, easy, quality, long
  prescription TEXT,         -- origem: auto_weekly, manual, etc
  readiness REAL,
  fatigue REAL,
  coach_mode TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT,
  PRIMARY KEY (athlete_id, plan_date),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);

-- ============================================
-- TABELA: daily_plan_ai
-- Plano detalhado gerado pela IA com constraints
-- ============================================
CREATE TABLE IF NOT EXISTS daily_plan_ai (
  athlete_id TEXT NOT NULL,
  plan_date TEXT NOT NULL,   -- YYYY-MM-DD
  allowed_type TEXT,         -- tipo permitido (vem do daily_plan)
  constraints_json TEXT,     -- JSON com todos os limites para a IA
  ai_workout_json TEXT,      -- JSON do treino gerado pela IA
  ai_model TEXT,             -- modelo usado (ex: gpt-5)
  status TEXT NOT NULL DEFAULT 'pending',  -- pending, accepted, rejected
  rejection_reason TEXT,     -- motivo se status=rejected
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT,
  PRIMARY KEY (athlete_id, plan_date),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);

-- ============================================
-- TRIGGER: Atualiza weekly_state apos insert em session_log
-- ============================================
CREATE TRIGGER IF NOT EXISTS trg_session_log_update_weekly
AFTER INSERT ON session_log
BEGIN
  INSERT INTO weekly_state (athlete_id, week_start, quality_days, long_days, total_time_min, total_load, total_distance_km)
  SELECT
    NEW.athlete_id,
    date(NEW.start_at, 'weekday 1', '-7 days') AS week_start,
    CASE WHEN NEW.tags LIKE '%quality%' THEN 1 ELSE 0 END,
    CASE WHEN NEW.tags LIKE '%long%' THEN 1 ELSE 0 END,
    COALESCE(NEW.duration_min, 0),
    COALESCE(NEW.trimp, 0),
    COALESCE(NEW.distance_km, 0)
  ON CONFLICT(athlete_id, week_start) DO UPDATE SET
    quality_days = weekly_state.quality_days + CASE WHEN NEW.tags LIKE '%quality%' THEN 1 ELSE 0 END,
    long_days = weekly_state.long_days + CASE WHEN NEW.tags LIKE '%long%' THEN 1 ELSE 0 END,
    total_time_min = weekly_state.total_time_min + COALESCE(NEW.duration_min, 0),
    total_load = weekly_state.total_load + COALESCE(NEW.trimp, 0),
    total_distance_km = weekly_state.total_distance_km + COALESCE(NEW.distance_km, 0),
    updated_at = datetime('now');
END;

-- ============================================
-- VIEWS uteis
-- ============================================

-- View: Resumo do atleta com ultimo treino
CREATE VIEW IF NOT EXISTS v_athlete_summary AS
SELECT
  p.athlete_id,
  p.name,
  p.hr_max,
  p.hr_rest,
  p.goal_event,
  s.readiness_score,
  s.fatigue_score,
  s.weekly_load,
  s.weekly_distance_km,
  s.coach_mode,
  (SELECT MAX(start_at) FROM session_log WHERE athlete_id = p.athlete_id) AS last_activity
FROM athlete_profile p
LEFT JOIN athlete_state s ON s.athlete_id = p.athlete_id;

-- View: Plano do dia com status
CREATE VIEW IF NOT EXISTS v_today_plan AS
SELECT
  dp.athlete_id,
  dp.plan_date,
  dp.workout_type,
  dp.readiness,
  dp.fatigue,
  dp.coach_mode,
  dai.status AS ai_status,
  dai.ai_model,
  json_extract(dai.ai_workout_json, '$.workout_title') AS workout_title,
  json_extract(dai.ai_workout_json, '$.total_duration_min') AS duration_min
FROM daily_plan dp
LEFT JOIN daily_plan_ai dai ON dai.athlete_id = dp.athlete_id AND dai.plan_date = dp.plan_date
WHERE dp.plan_date = date('now', 'localtime');
