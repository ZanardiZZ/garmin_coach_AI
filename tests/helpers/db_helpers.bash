#!/bin/bash
# db_helpers.bash - Helpers para operações de database

# Executa query SQL e retorna resultado
db_query() {
  local db_path=$1
  local query=$2

  sqlite3 "$db_path" "$query"
}

# Executa query SQL sem output
db_exec() {
  local db_path=$1
  local query=$2

  sqlite3 "$db_path" "$query" >/dev/null
}

# Retorna valor de uma célula
db_get_value() {
  local db_path=$1
  local query=$2

  sqlite3 "$db_path" "$query" | head -n1
}

# Retorna contagem de registros
db_count() {
  local db_path=$1
  local table=$2
  local where_clause="${3:-}"

  local query="SELECT COUNT(*) FROM $table"
  if [[ -n "$where_clause" ]]; then
    query="$query WHERE $where_clause"
  fi

  db_get_value "$db_path" "$query"
}

# Verifica se registro existe
db_exists() {
  local db_path=$1
  local table=$2
  local where_clause=$3

  local count=$(db_count "$db_path" "$table" "$where_clause")
  [[ "$count" -gt 0 ]]
}

# Limpa tabela
db_clear_table() {
  local db_path=$1
  local table=$2

  db_exec "$db_path" "DELETE FROM $table;"
}

# Insere atleta padrão
db_insert_default_athlete() {
  local db_path=$1
  local athlete_id="${2:-test_athlete}"

  sqlite3 "$db_path" <<EOF
INSERT OR REPLACE INTO athlete_profile (
  athlete_id, hr_max, hr_rest, goal_event, goal_date
)
VALUES (
  '$athlete_id', 185, 48, 'Test Ultra 12h', '2026-06-15'
);

INSERT OR REPLACE INTO athlete_state (
  athlete_id, state_date, coach_mode,
  readiness_score, fatigue_score, monotony_index, strain_index,
  avg_7d_load, avg_28d_load, cv_7d_load,
  last_quality_date, last_long_date, days_since_quality, days_since_long
)
VALUES (
  '$athlete_id', '2026-01-18', 'moderate',
  75.0, 50.0, 1.2, 85.0,
  100.0, 95.0, 0.15,
  '2026-01-15', '2026-01-12', 3, 6
);

INSERT OR REPLACE INTO weekly_state (
  athlete_id, week_start_date,
  quality_days, long_days, total_days,
  total_time_min, total_load, avg_daily_load
)
VALUES (
  '$athlete_id', '2026-01-13',
  1, 0, 3,
  180, 250.0, 83.3
);
EOF
}

# Insere sessões de treino de exemplo
db_insert_sample_sessions() {
  local db_path=$1
  local athlete_id="${2:-test_athlete}"
  local base_date="${3:-2026-01-15}"

  # Sessão easy
  sqlite3 "$db_path" <<EOF
INSERT OR REPLACE INTO session_log (
  athlete_id, session_date, duration_min, distance_km, avg_hr,
  elevation_gain_m, calories, tag, load_trimp, notes
)
VALUES
  ('$athlete_id', '$base_date', 60, 10.0, 145, 100, 500, 'easy', 80.0, 'Easy run'),
  ('$athlete_id', date('$base_date', '-1 day'), 45, 7.5, 142, 80, 380, 'easy', 60.0, 'Recovery'),
  ('$athlete_id', date('$base_date', '-2 days'), 75, 12.0, 155, 150, 650, 'quality', 110.0, 'Intervals'),
  ('$athlete_id', date('$base_date', '-5 days'), 120, 20.0, 148, 300, 1100, 'long', 150.0, 'Long run'),
  ('$athlete_id', date('$base_date', '-7 days'), 50, 8.0, 140, 90, 420, 'easy', 65.0, 'Easy');
EOF
}

# Insere body composition de exemplo
db_insert_sample_body_comp() {
  local db_path=$1
  local athlete_id="${2:-test_athlete}"
  local base_date="${3:-2026-01-18}"

  sqlite3 "$db_path" <<EOF
INSERT OR REPLACE INTO body_comp_log (
  athlete_id, measure_date, weight_kg, body_fat_pct,
  skeletal_muscle_mass_kg, bone_mass_kg, body_water_pct
)
VALUES
  ('$athlete_id', '$base_date', 70.5, 12.5, 35.2, 3.1, 62.0),
  ('$athlete_id', date('$base_date', '-7 days'), 71.0, 13.0, 35.0, 3.1, 61.5),
  ('$athlete_id', date('$base_date', '-14 days'), 71.3, 13.2, 34.8, 3.1, 61.2);
EOF
}

# Insere coach policy padrão
db_insert_default_policies() {
  local db_path=$1

  sqlite3 "$db_path" <<EOF
INSERT OR REPLACE INTO coach_policy (
  mode, readiness_floor, fatigue_cap,
  max_hard_days_week, max_quality_week_min, max_long_week_min,
  min_long_run_km, max_long_run_km
)
VALUES
  ('conservative', 70, 60, 2, 120, 240, 18, 35),
  ('moderate', 65, 70, 3, 150, 300, 18, 40),
  ('aggressive', 60, 80, 4, 180, 360, 20, 45);
EOF
}

# Cria database completo de teste
db_create_full_test_db() {
  local db_path=$1
  local athlete_id="${2:-test_athlete}"

  # Aplica schema
  local test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local schema_path="$test_dir/../sql/schema.sql"

  sqlite3 "$db_path" < "$schema_path"

  # Insere dados
  db_insert_default_policies "$db_path"
  db_insert_default_athlete "$db_path" "$athlete_id"
  db_insert_sample_sessions "$db_path" "$athlete_id"
  db_insert_sample_body_comp "$db_path" "$athlete_id"
}

# Retorna último plano diário
db_get_latest_plan() {
  local db_path=$1
  local athlete_id="${2:-test_athlete}"

  sqlite3 "$db_path" "SELECT plan_date, workout_type, duration_min FROM daily_plan WHERE athlete_id='$athlete_id' ORDER BY plan_date DESC LIMIT 1;"
}

# Retorna último workout AI
db_get_latest_ai_workout() {
  local db_path=$1
  local athlete_id="${2:-test_athlete}"

  sqlite3 "$db_path" "SELECT ai_workout_json FROM daily_plan_ai WHERE athlete_id='$athlete_id' AND status='accepted' ORDER BY plan_date DESC LIMIT 1;"
}

# Verifica se migration foi aplicada
db_is_migration_applied() {
  local db_path=$1
  local migration_name=$2

  db_exists "$db_path" "schema_migrations" "migration_name='$migration_name'"
}

# Aplica migration
db_apply_migration() {
  local db_path=$1
  local migration_file=$2

  sqlite3 "$db_path" < "$migration_file"
}

# Dumpa database para arquivo
db_dump() {
  local db_path=$1
  local output_file=$2

  sqlite3 "$db_path" .dump > "$output_file"
}

# Restaura database de dump
db_restore() {
  local db_path=$1
  local dump_file=$2

  sqlite3 "$db_path" < "$dump_file"
}

# Retorna informações de esquema de tabela
db_get_table_info() {
  local db_path=$1
  local table=$2

  sqlite3 "$db_path" "PRAGMA table_info($table);"
}

# Lista todas as tabelas
db_list_tables() {
  local db_path=$1

  sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
}

# Lista todos os triggers
db_list_triggers() {
  local db_path=$1

  sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='trigger' ORDER BY name;"
}

# Lista todos os índices
db_list_indexes() {
  local db_path=$1

  sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='index' ORDER BY name;"
}
