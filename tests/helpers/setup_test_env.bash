#!/bin/bash
# setup_test_env.bash - Helper para configurar ambiente de teste

# Carrega libs BATS
load_bats_libs() {
  local test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  load "$test_dir/bats-libs/bats-support/load"
  load "$test_dir/bats-libs/bats-assert/load"
  load "$test_dir/bats-libs/bats-file/load"
}

# Cria diretório temporário para teste
setup_test_dir() {
  export TEST_TEMP_DIR=$(mktemp -d -t ultra-coach-test.XXXXXX)
  export TEST_DB="$TEST_TEMP_DIR/test_coach.sqlite"
  export TEST_DATA_DIR="$TEST_TEMP_DIR/data"
  export TEST_LOG_DIR="$TEST_TEMP_DIR/logs"
  export TEST_EXPORT_DIR="$TEST_TEMP_DIR/exports"

  mkdir -p "$TEST_DATA_DIR" "$TEST_LOG_DIR" "$TEST_EXPORT_DIR"
}

# Limpa diretório temporário
teardown_test_dir() {
  if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Configura variáveis de ambiente para testes
setup_test_env_vars() {
  export ULTRA_COACH_PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-/opt/ultra-coach}"
  export ULTRA_COACH_DATA_DIR="${TEST_DATA_DIR:-$TEST_TEMP_DIR/data}"
  export ULTRA_COACH_DB="${TEST_DB:-$TEST_TEMP_DIR/test_coach.sqlite}"
  export ULTRA_COACH_PROMPT_FILE="$ULTRA_COACH_PROJECT_DIR/templates/coach_prompt_ultra.txt"
  export ULTRA_COACH_FIT_DIR="$ULTRA_COACH_PROJECT_DIR/fit"

  export ATHLETE="${ATHLETE:-test_athlete}"

  # Mock de APIs
  export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-test-mock-key}"
  export MODEL="${MODEL:-gpt-4o}"

  export INFLUX_URL="${INFLUX_URL:-http://localhost:18086/query}"
  export INFLUX_DB="${INFLUX_DB:-TestGarminStats}"
  export INFLUX_USER="${INFLUX_USER:-}"
  export INFLUX_PASS="${INFLUX_PASS:-}"

  export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
  export TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

  export WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:18088/webhook/test}"
}

# Copia fixture de database
load_db_fixture() {
  local fixture_name=$1
  local test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local fixture_path="$test_dir/fixtures/databases/${fixture_name}.sqlite"

  if [[ ! -f "$fixture_path" ]]; then
    echo "ERROR: Fixture não encontrado: $fixture_path" >&2
    return 1
  fi

  cp "$fixture_path" "$TEST_DB"
}

# Inicializa database vazio com schema
init_empty_db() {
  local test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local schema_path="$test_dir/../sql/schema.sql"

  if [[ ! -f "$schema_path" ]]; then
    echo "ERROR: Schema não encontrado: $schema_path" >&2
    return 1
  fi

  sqlite3 "$TEST_DB" < "$schema_path"
}

# Insere atleta de teste
insert_test_athlete() {
  local athlete_id="${1:-test_athlete}"
  local hr_max="${2:-185}"
  local hr_rest="${3:-48}"

  sqlite3 "$TEST_DB" <<EOF
INSERT OR REPLACE INTO athlete_profile (athlete_id, hr_max, hr_rest, goal_event, weekly_hours_target)
VALUES ('$athlete_id', $hr_max, $hr_rest, 'Test Ultra 12h', 10.0);
EOF
}

# Insere sessão de treino de teste
insert_test_session() {
  local athlete_id="${1:-test_athlete}"
  local session_date="${2:-2026-01-15}"
  local duration_min="${3:-60}"
  local distance_km="${4:-10.0}"
  local avg_hr="${5:-145}"
  local tag="${6:-easy}"

  sqlite3 "$TEST_DB" <<EOF
INSERT OR REPLACE INTO session_log (
  athlete_id, start_at, duration_min, distance_km, avg_hr,
  max_hr, avg_pace_min_km, trimp, tags, notes
)
VALUES (
  '$athlete_id', '$session_date 06:00:00', $duration_min, $distance_km, $avg_hr,
  165, 6.0, 85.5, '$tag', 'Test session'
);
EOF
}

# Verifica se comando existe
require_command() {
  local cmd=$1
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Comando necessário não encontrado: $cmd" >&2
    return 1
  fi
}

# Aguarda até que condição seja verdadeira (timeout em segundos)
wait_for_condition() {
  local condition_cmd=$1
  local timeout=${2:-10}
  local interval=${3:-0.5}

  local elapsed=0
  while ! eval "$condition_cmd"; do
    sleep "$interval"
    elapsed=$(echo "$elapsed + $interval" | bc)

    if (( $(echo "$elapsed >= $timeout" | bc -l) )); then
      return 1
    fi
  done

  return 0
}

# Mock de servidor HTTP simples (netcat)
start_mock_server() {
  local port=$1
  local response_file=$2
  local pid_file="${3:-$TEST_TEMP_DIR/mock_server_${port}.pid}"

  if [[ ! -f "$response_file" ]]; then
    echo "ERROR: Arquivo de resposta não encontrado: $response_file" >&2
    return 1
  fi

  # Start server em background
  (
    while true; do
      cat "$response_file" | nc -l -p "$port" -q 1 || true
    done
  ) &

  echo $! > "$pid_file"
}

# Para servidor mock
stop_mock_server() {
  local pid_file=$1

  if [[ -f "$pid_file" ]]; then
    local pid=$(cat "$pid_file")
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
}
