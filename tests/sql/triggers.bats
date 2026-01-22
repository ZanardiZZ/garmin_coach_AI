#!/usr/bin/env bats

# Testes para triggers SQL

setup() {
  # Carrega helpers
  local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  load "$test_dir/helpers/setup_test_env"
  load "$test_dir/helpers/assert_helpers"
  load "$test_dir/helpers/db_helpers"
  load_bats_libs

  setup_test_dir
  setup_test_env_vars

  # Cria database completo
  db_create_full_test_db "$TEST_DB" "test_athlete"
}

teardown() {
  teardown_test_dir
}

@test "valida que trigger trg_session_log_update_weekly existe" {
  run db_list_triggers "$TEST_DB"

  assert_success
  assert_contains "$output" "trg_session_log_update_weekly"
}

@test "valida que inserir sessão atualiza weekly_state" {
  # Limpa weekly_state
  db_clear_table "$TEST_DB" "weekly_state"

  # Insere nova sessão
  sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (
  athlete_id, start_at, duration_min, distance_km, avg_hr,
  max_hr, avg_pace_min_km, trimp, tags, notes
)
VALUES (
  'test_athlete', '2026-01-18 06:00:00', 60, 10.0, 145,
  168, 5.6, 85.5, 'easy', 'Trigger test'
);
EOF

  # Verifica que weekly_state foi criado
  run db_exists "$TEST_DB" "weekly_state" "athlete_id='test_athlete'"

  assert_success
}

@test "valida que trigger incrementa quality_days para tag=quality" {
  # Limpa e insere baseline
  db_clear_table "$TEST_DB" "weekly_state"

  # Insere sessão quality
  sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (
  athlete_id, start_at, duration_min, distance_km, avg_hr,
  tags, trimp
)
VALUES (
  'test_athlete', '2026-01-14 06:00:00', 75, 12.0, 158,
  'quality', 110.0
);
EOF

  # Verifica quality_days
  run sqlite3 "$TEST_DB" "SELECT quality_days FROM weekly_state WHERE athlete_id='test_athlete' AND week_start=date('2026-01-14','weekday 1','-7 days');"

  assert_success
  [[ "$output" -ge 1 ]]
}

@test "valida que trigger incrementa long_days para tag=long" {
  # Limpa e insere baseline
  db_clear_table "$TEST_DB" "weekly_state"

  # Insere sessão long
  sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (
  athlete_id, start_at, duration_min, distance_km, avg_hr,
  tags, trimp
)
VALUES (
  'test_athlete', '2026-01-18 06:00:00', 120, 20.0, 148,
  'long', 150.0
);
EOF

  # Verifica long_days
  run sqlite3 "$TEST_DB" "SELECT long_days FROM weekly_state WHERE athlete_id='test_athlete' AND week_start=date('2026-01-18','weekday 1','-7 days');"

  assert_success
  [[ "$output" -ge 1 ]]
}

@test "valida que trigger não incrementa quality/long_days para tag=easy" {
  # Limpa e insere baseline
  db_clear_table "$TEST_DB" "weekly_state"

  # Insere apenas sessão easy
  sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (
  athlete_id, start_at, duration_min, distance_km, avg_hr,
  tags, trimp
)
VALUES (
  'test_athlete', '2026-01-18 06:00:00', 60, 10.0, 145,
  'easy', 85.5
);
EOF

  # Verifica que quality_days e long_days são 0
  run sqlite3 "$TEST_DB" "SELECT quality_days, long_days FROM weekly_state WHERE athlete_id='test_athlete' AND week_start=date('2026-01-18','weekday 1','-7 days');"

  assert_success
  assert_output "0|0"
}

@test "valida que trigger calcula total_time_min corretamente" {
  # Limpa e insere 2 sessões
  db_clear_table "$TEST_DB" "weekly_state"

  sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (athlete_id, start_at, duration_min, tags, trimp)
VALUES
  ('test_athlete', '2026-01-14 06:00:00', 60, 'easy', 85.0),
  ('test_athlete', '2026-01-15 06:00:00', 45, 'easy', 60.0);
EOF

  # Verifica total_time_min = 105
  run sqlite3 "$TEST_DB" "SELECT total_time_min FROM weekly_state WHERE athlete_id='test_athlete' AND week_start=date('2026-01-14','weekday 1','-7 days');"

  assert_success
  assert_output "105"
}

@test "valida que trigger calcula total_load corretamente" {
  # Limpa e insere 2 sessões
  db_clear_table "$TEST_DB" "weekly_state"

  sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (athlete_id, start_at, duration_min, tags, trimp)
VALUES
  ('test_athlete', '2026-01-14 06:00:00', 60, 'easy', 85.0),
  ('test_athlete', '2026-01-15 06:00:00', 45, 'easy', 60.0);
EOF

  # Verifica total_load = 145.0
  run sqlite3 "$TEST_DB" "SELECT total_load FROM weekly_state WHERE athlete_id='test_athlete' AND week_start=date('2026-01-14','weekday 1','-7 days');"

  assert_success
  assert_output "145.0"
}

@test "valida que trigger agrupa por semana corretamente" {
  # Limpa
  db_clear_table "$TEST_DB" "weekly_state"

  # Insere sessões em 2 semanas diferentes
  sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (athlete_id, start_at, duration_min, tags, trimp)
VALUES
  ('test_athlete', '2026-01-14 06:00:00', 60, 'easy', 85.0),  -- Semana 1
  ('test_athlete', '2026-01-20 06:00:00', 60, 'easy', 85.0);  -- Semana 2
EOF

  # Deve ter 2 registros em weekly_state
  run db_count "$TEST_DB" "weekly_state" "athlete_id='test_athlete'"

  assert_success
  assert_output "2"
}

@test "valida que trigger não quebra em sessão sem trimp" {
  # Limpa
  db_clear_table "$TEST_DB" "weekly_state"

  # Insere sessão sem trimp (NULL)
  sqlite3 "$TEST_DB" <<EOF
INSERT INTO session_log (athlete_id, start_at, duration_min, tags)
VALUES
  ('test_athlete', '2026-01-18 06:00:00', 60, 'easy');
EOF

  # Deve criar weekly_state mesmo com load NULL
  run db_exists "$TEST_DB" "weekly_state" "athlete_id='test_athlete'"

  assert_success
}
