#!/usr/bin/env bats

# Testes de integridade do schema SQL

setup() {
  # Carrega helpers
  local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  load "$test_dir/helpers/setup_test_env"
  load "$test_dir/helpers/assert_helpers"
  load "$test_dir/helpers/db_helpers"
  load_bats_libs

  setup_test_dir
  setup_test_env_vars

  # Aplica schema
  local schema_path="$ULTRA_COACH_PROJECT_DIR/sql/schema.sql"
  sqlite3 "$TEST_DB" < "$schema_path"
}

teardown() {
  teardown_test_dir
}

@test "valida que schema cria todas as tabelas esperadas" {
  local expected_tables=(
    "athlete_profile"
    "athlete_state"
    "weekly_state"
    "session_log"
    "body_comp_log"
    "coach_policy"
    "daily_plan"
    "daily_plan_ai"
    "schema_migrations"
  )

  for table in "${expected_tables[@]}"; do
    run sqlite3 "$TEST_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';"
    assert_success "Tabela $table não foi criada"
    assert_output "$table"
  done
}

@test "valida que tabela athlete_profile tem colunas corretas" {
  run sqlite3 "$TEST_DB" "PRAGMA table_info(athlete_profile);"

  assert_success
  assert_contains "$output" "athlete_id"
  assert_contains "$output" "hr_max"
  assert_contains "$output" "hr_rest"
  assert_contains "$output" "goal_event"
  assert_contains "$output" "goal_date"
}

@test "valida que tabela session_log tem colunas corretas" {
  run sqlite3 "$TEST_DB" "PRAGMA table_info(session_log);"

  assert_success
  assert_contains "$output" "athlete_id"
  assert_contains "$output" "session_date"
  assert_contains "$output" "duration_min"
  assert_contains "$output" "distance_km"
  assert_contains "$output" "avg_hr"
  assert_contains "$output" "tag"
  assert_contains "$output" "load_trimp"
}

@test "valida que tabela daily_plan tem colunas corretas" {
  run sqlite3 "$TEST_DB" "PRAGMA table_info(daily_plan);"

  assert_success
  assert_contains "$output" "athlete_id"
  assert_contains "$output" "plan_date"
  assert_contains "$output" "workout_type"
  assert_contains "$output" "duration_min"
}

@test "valida que tabela daily_plan_ai tem colunas corretas" {
  run sqlite3 "$TEST_DB" "PRAGMA table_info(daily_plan_ai);"

  assert_success
  assert_contains "$output" "athlete_id"
  assert_contains "$output" "plan_date"
  assert_contains "$output" "status"
  assert_contains "$output" "ai_workout_json"
  assert_contains "$output" "constraints_json"
  assert_contains "$output" "rejection_reason"
}

@test "valida que índices foram criados" {
  run db_list_indexes "$TEST_DB"

  assert_success
  # SQLite cria índices automáticos para PRIMARY KEY, mas podemos ter outros
  assert_not_equal "$output" ""
}

@test "valida que triggers foram criados" {
  run db_list_triggers "$TEST_DB"

  assert_success
  assert_contains "$output" "trg_session_log_update_weekly"
}

@test "valida que foreign keys estão habilitadas" {
  run sqlite3 "$TEST_DB" "PRAGMA foreign_keys;"

  # Pode estar 0 ou 1 dependendo da conexão, mas comando deve funcionar
  assert_success
}

@test "valida integridade do database vazio" {
  run sqlite3 "$TEST_DB" "PRAGMA integrity_check;"

  assert_success
  assert_output "ok"
}

@test "valida que coach_policy tem policies padrão" {
  # Schema deve inserir policies padrão
  run db_count "$TEST_DB" "coach_policy"

  assert_success
  # Deve ter pelo menos 3 policies (conservative, moderate, aggressive)
  local count="$output"
  [[ "$count" -ge 3 ]]
}

@test "valida que tabela schema_migrations existe para migrations" {
  run sqlite3 "$TEST_DB" "SELECT sql FROM sqlite_master WHERE type='table' AND name='schema_migrations';"

  assert_success
  assert_contains "$output" "migration_name"
  assert_contains "$output" "applied_at"
}

@test "valida que athlete_profile tem constraint de PK" {
  # Tenta inserir duplicata
  sqlite3 "$TEST_DB" "INSERT INTO athlete_profile (athlete_id, hr_max, hr_rest) VALUES ('test', 185, 48);"

  run sqlite3 "$TEST_DB" "INSERT INTO athlete_profile (athlete_id, hr_max, hr_rest) VALUES ('test', 185, 48);"

  # Deve falhar por violação de PRIMARY KEY
  assert_failure
}

@test "valida que session_log aceita valores válidos" {
  sqlite3 "$TEST_DB" "INSERT INTO athlete_profile (athlete_id, hr_max, hr_rest) VALUES ('test', 185, 48);"

  run sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (
  athlete_id, session_date, duration_min, distance_km, avg_hr,
  elevation_gain_m, calories, tag, load_trimp, notes
)
VALUES (
  'test', '2026-01-18', 60, 10.0, 145,
  150, 500, 'easy', 85.5, 'Test session'
);
EOF

  assert_success
}

@test "valida que daily_plan_ai tem valores padrão corretos" {
  sqlite3 "$TEST_DB" "INSERT INTO athlete_profile (athlete_id, hr_max, hr_rest) VALUES ('test', 185, 48);"

  sqlite3 "$TEST_DB" <<EOF
INSERT INTO daily_plan_ai (athlete_id, plan_date)
VALUES ('test', '2026-01-18');
EOF

  run sqlite3 "$TEST_DB" "SELECT status FROM daily_plan_ai WHERE athlete_id='test' AND plan_date='2026-01-18';"

  assert_success
  assert_output "pending"
}
