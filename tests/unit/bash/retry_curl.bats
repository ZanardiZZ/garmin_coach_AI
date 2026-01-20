#!/usr/bin/env bats

# Testes para função retry_curl do run_coach_daily.sh

setup() {
  # Carrega helpers
  local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  load "$test_dir/helpers/setup_test_env"
  load_bats_libs

  # Setup test directory
  setup_test_dir
  setup_test_env_vars

  # Source da função retry_curl
  source "$ULTRA_COACH_PROJECT_DIR/bin/run_coach_daily.sh" 2>/dev/null || true

  # Mock da função log_warn para evitar output desnecessário
  log_warn() { echo "[WARN] $*" >&2; }

  # Diretório para outputs de teste
  TEST_OUTPUT="$TEST_TEMP_DIR/output.txt"
}

teardown() {
  # Mata servidor mock se ainda estiver rodando
  if [[ -n "${MOCK_SERVER_PID:-}" ]]; then
    kill "$MOCK_SERVER_PID" 2>/dev/null || true
  fi

  teardown_test_dir
}

# Helper para iniciar servidor HTTP mock
start_http_mock() {
  local port=$1
  local response_code=$2
  local response_body="${3:-OK}"

  # Cria script de resposta HTTP
  local response_file="$TEST_TEMP_DIR/http_response.txt"
  cat > "$response_file" <<EOF
HTTP/1.1 $response_code OK
Content-Type: text/plain
Content-Length: ${#response_body}

$response_body
EOF

  # Inicia servidor em background
  (
    while true; do
      cat "$response_file" | nc -l -p "$port" -q 1 2>/dev/null || true
      sleep 0.1
    done
  ) &

  MOCK_SERVER_PID=$!

  # Aguarda servidor ficar disponível
  sleep 0.5
}

@test "valida que retry_curl retorna sucesso em 200" {
  start_http_mock 18801 200 "Success"

  run retry_curl 3 "$TEST_OUTPUT" "http://localhost:18801/test"

  assert_success
  assert_output "200"
  assert_file_exist "$TEST_OUTPUT"

  run cat "$TEST_OUTPUT"
  assert_output "Success"
}

@test "valida que retry_curl retorna sucesso em 201" {
  start_http_mock 18802 201 "Created"

  run retry_curl 3 "$TEST_OUTPUT" "http://localhost:18802/test"

  assert_success
  assert_output "201"
}

@test "valida que retry_curl não faz retry em erro 4xx" {
  start_http_mock 18803 404 "Not Found"

  run retry_curl 3 "$TEST_OUTPUT" "http://localhost:18803/test"

  # Deve retornar sucesso (não é erro de rede/servidor)
  assert_success
  assert_output "404"
}

@test "valida que retry_curl não faz retry em erro 401" {
  start_http_mock 18804 401 "Unauthorized"

  run retry_curl 3 "$TEST_OUTPUT" "http://localhost:18804/test"

  assert_success
  assert_output "401"
}

@test "valida que retry_curl faz retry em erro 500" {
  skip "Teste requer servidor mock mais sofisticado que pode mudar resposta"

  # TODO: Implementar mock que retorna 500 nas primeiras tentativas e 200 na última
}

@test "valida que retry_curl usa backoff exponencial" {
  skip "Teste requer medição de timing entre retries"

  # TODO: Implementar teste que verifica os delays: 2s, 4s, 8s
}

@test "valida que retry_curl falha após max_attempts em erro 5xx" {
  # Servidor que sempre retorna 500
  start_http_mock 18805 500 "Internal Server Error"

  run timeout 10 retry_curl 3 "$TEST_OUTPUT" "http://localhost:18805/test"

  assert_failure
  assert_output "500"
}

@test "valida que retry_curl funciona com headers customizados" {
  start_http_mock 18806 200 "OK"

  run retry_curl 3 "$TEST_OUTPUT" \
    -H "Authorization: Bearer test-token" \
    -H "Content-Type: application/json" \
    "http://localhost:18806/test"

  assert_success
  assert_output "200"
}

@test "valida que retry_curl funciona com POST data" {
  start_http_mock 18807 200 "OK"

  run retry_curl 3 "$TEST_OUTPUT" \
    -X POST \
    -d '{"test":"data"}' \
    "http://localhost:18807/test"

  assert_success
  assert_output "200"
}
