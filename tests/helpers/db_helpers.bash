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
  athlete_id, hr_max, hr_rest, weight_kg, lt_hr, lt_pace_min_km, lt_power_w, goal_event, weekly_hours_target
)
VALUES (
  '$athlete_id', 185, 48, 72.0, 165, 4.5, 320, 'Test Ultra 12h', 10.0
);

INSERT OR REPLACE INTO athlete_state (
  athlete_id, readiness_score, fatigue_score, monotony, strain,
  weekly_load, weekly_distance_km, weekly_time_min,
  last_long_run_km, last_long_run_at, last_quality_at, coach_mode, updated_at
)
VALUES (
  '$athlete_id', 75.0, 50.0, 1.2, 85.0,
  210.0, 42.0, 240.0,
  28.0, '2026-01-12 06:00:00', '2026-01-15 06:00:00', 'moderate', datetime('now')
);

INSERT OR REPLACE INTO weekly_state (
  athlete_id, week_start,
  quality_days, long_days, total_time_min, total_load, total_distance_km, updated_at
)
VALUES (
  '$athlete_id', '2026-01-13',
  1, 0, 180, 250.0, 42.0, datetime('now')
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
  athlete_id, start_at, duration_min, distance_km, avg_hr,
  max_hr, avg_pace_min_km, trimp, tags, notes
)
VALUES
  ('$athlete_id', '$base_date 06:00:00', 60, 10.0, 145, 168, 6.0, 80.0, 'easy', 'Easy run'),
  ('$athlete_id', date('$base_date', '-1 day') || ' 06:00:00', 45, 7.5, 142, 160, 6.4, 60.0, 'easy', 'Recovery'),
  ('$athlete_id', date('$base_date', '-2 days') || ' 06:00:00', 75, 12.0, 155, 178, 5.8, 110.0, 'quality', 'Intervals'),
  ('$athlete_id', date('$base_date', '-5 days') || ' 06:00:00', 120, 20.0, 148, 172, 6.5, 150.0, 'long', 'Long run'),
  ('$athlete_id', date('$base_date', '-7 days') || ' 06:00:00', 50, 8.0, 140, 158, 6.2, 65.0, 'easy', 'Easy');
EOF
}

# Insere body composition de exemplo
db_insert_sample_body_comp() {
  local db_path=$1
  local athlete_id="${2:-test_athlete}"
  local base_date="${3:-2026-01-18}"

  sqlite3 "$db_path" <<EOF
INSERT OR REPLACE INTO body_comp_log (
  athlete_id, measured_at, device, bmi, body_fat_pct, body_water_pct,
  bone_mass_kg, muscle_mass_kg, weight_kg
)
VALUES
  ('$athlete_id', '$base_date 07:00:00', 'Index S2', 22.5, 12.5, 62.0, 3.1, 35.2, 70.5),
  ('$athlete_id', date('$base_date', '-7 days') || ' 07:00:00', 'Index S2', 22.7, 13.0, 61.5, 3.1, 35.0, 71.0),
  ('$athlete_id', date('$base_date', '-14 days') || ' 07:00:00', 'Index S2', 22.8, 13.2, 61.2, 3.1, 34.8, 71.3);
EOF
}

# Insere coach policy padrão
db_insert_default_policies() {
  local db_path=$1

  sqlite3 "$db_path" <<EOF
INSERT OR REPLACE INTO coach_policy (
  mode, readiness_floor, fatigue_cap, max_hard_days_week, max_long_days_week, notes
)
VALUES
  ('conservative', 70, 60, 1, 1, 'Test conservative'),
  ('moderate', 60, 70, 2, 1, 'Test moderate'),
  ('aggressive', 50, 80, 2, 2, 'Test aggressive');
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

  sqlite3 "$db_path" "SELECT plan_date, workout_type FROM daily_plan WHERE athlete_id='$athlete_id' ORDER BY plan_date DESC LIMIT 1;"
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
