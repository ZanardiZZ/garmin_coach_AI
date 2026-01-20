#!/usr/bin/env bats

# Testes para função sql_escape do sync_influx_to_sqlite.sh
# Previne SQL injection dobrando aspas simples: ' -> ''

setup() {
  # Carrega helpers
  local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  load "$test_dir/helpers/setup_test_env"
  load_bats_libs

  # Source da função sql_escape
  source "$ULTRA_COACH_PROJECT_DIR/bin/sync_influx_to_sqlite.sh" 2>/dev/null || true
}

@test "valida que string sem aspas permanece inalterada" {
  run sql_escape "Morning Run"

  assert_success
  assert_output "Morning Run"
}

@test "valida que aspas simples são duplicadas" {
  run sql_escape "O'Brien's Run"

  assert_success
  assert_output "O''Brien''s Run"
}

@test "valida que múltiplas aspas são duplicadas" {
  run sql_escape "It's John's 'special' run"

  assert_success
  assert_output "It''s John''s ''special'' run"
}

@test "valida que tentativa de SQL injection é neutralizada" {
  # Tentativa clássica: ' OR '1'='1
  run sql_escape "' OR '1'='1"

  assert_success
  assert_output "'' OR ''1''=''1"
}

@test "valida que tentativa de DROP TABLE é neutralizada" {
  # Tentativa: '; DROP TABLE session_log; --
  run sql_escape "'; DROP TABLE session_log; --"

  assert_success
  assert_output "''; DROP TABLE session_log; --"
}

@test "valida que tentativa de UNION injection é neutralizada" {
  # Tentativa: ' UNION SELECT * FROM athlete_profile WHERE ''='
  run sql_escape "' UNION SELECT * FROM athlete_profile WHERE ''='"

  assert_success
  assert_output "'' UNION SELECT * FROM athlete_profile WHERE ''''=''"
}

@test "valida que string vazia retorna string vazia" {
  run sql_escape ""

  assert_success
  assert_output ""
}

@test "valida que apenas uma aspa simples é duplicada" {
  run sql_escape "'"

  assert_success
  assert_output "''"
}

@test "valida que aspas consecutivas são todas duplicadas" {
  run sql_escape "'''"

  assert_success
  assert_output "''''''"
}

@test "valida que caracteres especiais além de aspas não são modificados" {
  # Tabs, newlines, backslashes, etc não devem ser alterados
  run sql_escape 'Test\nWith\tSpecial"Chars'

  assert_success
  assert_output 'Test\nWith\tSpecial"Chars'
}

@test "valida que aspas duplas não são modificadas" {
  # SQL usa aspas simples para strings, aspas duplas para identificadores
  run sql_escape 'Test "quoted" string'

  assert_success
  assert_output 'Test "quoted" string'
}

@test "valida integração com SQLite" {
  setup_test_dir
  local test_db="$TEST_TEMP_DIR/test.sqlite"

  # Cria tabela simples
  sqlite3 "$test_db" "CREATE TABLE test (name TEXT);"

  # String maliciosa
  local malicious_name="Robert'); DROP TABLE test; --"
  local escaped_name=$(sql_escape "$malicious_name")

  # Insere usando string escapada
  sqlite3 "$test_db" "INSERT INTO test (name) VALUES ('$escaped_name');"

  # Verifica que tabela ainda existe
  run sqlite3 "$test_db" "SELECT name FROM sqlite_master WHERE type='table' AND name='test';"
  assert_success
  assert_output "test"

  # Verifica que string foi inserida corretamente
  run sqlite3 "$test_db" "SELECT name FROM test;"
  assert_success
  assert_output "$malicious_name"

  teardown_test_dir
}

@test "valida que nomes de atividades reais são escapados corretamente" {
  # Casos reais que podem conter aspas
  run sql_escape "Coach's Morning Run"
  assert_output "Coach''s Morning Run"

  run sql_escape "It's a beautiful day"
  assert_output "It''s a beautiful day"

  run sql_escape "Women's 10K Race"
  assert_output "Women''s 10K Race"
}

@test "valida que texto em português com aspas funciona" {
  run sql_escape "Corrida do Dia D'Avila"
  assert_output "Corrida do Dia D''Avila"

  run sql_escape "Treino 'pesado' hoje"
  assert_output "Treino ''pesado'' hoje"
}

@test "valida que whitespace é preservado" {
  run sql_escape "Test   with   spaces"
  assert_output "Test   with   spaces"

  run sql_escape "Test
with
newlines"
  assert_output "Test
with
newlines"
}
