#!/bin/bash
# test_e2e_helper.sh - Helper para testes E2E manuais

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-/opt/ultra-coach}"
DATA_DIR="${ULTRA_COACH_DATA_DIR:-/var/lib/ultra-coach}"
DB="${ULTRA_COACH_DB:-$DATA_DIR/coach.sqlite}"
TEST_ATHLETE="${TEST_ATHLETE:-test_e2e}"

# Funções auxiliares
log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
  echo -e "${GREEN}✅${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}⚠️${NC}  $*"
}

log_error() {
  echo -e "${RED}❌${NC} $*"
}

separator() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# Comandos
cmd_check_prereqs() {
  echo "🔍 Verificando pré-requisitos..."
  echo ""

  local all_ok=true

  # Binários
  for cmd in sqlite3 jq curl node bc; do
    if command -v "$cmd" &>/dev/null; then
      log_success "$cmd instalado"
    else
      log_error "$cmd NÃO ENCONTRADO"
      all_ok=false
    fi
  done

  # Node.js version
  if command -v node &>/dev/null; then
    node_version=$(node --version | sed 's/v//' | cut -d. -f1)
    if [[ "$node_version" -ge 18 ]]; then
      log_success "Node.js versão OK ($node_version)"
    else
      log_error "Node.js versão inadequada ($node_version < 18)"
      all_ok=false
    fi
  fi

  # Scripts no PATH
  if command -v run_coach_daily.sh &>/dev/null; then
    log_success "Scripts no PATH"
  else
    log_warn "Scripts não estão no PATH"
    echo "   Execute: sudo ln -sf $PROJECT_DIR/bin/* /usr/local/bin/"
  fi

  # Arquivo de configuração
  if [[ -f /etc/ultra-coach/env ]]; then
    log_success "Arquivo /etc/ultra-coach/env existe"

    source /etc/ultra-coach/env

    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
      log_success "OPENAI_API_KEY configurado"
    else
      log_error "OPENAI_API_KEY NÃO configurado"
      all_ok=false
    fi
  else
    log_error "Arquivo /etc/ultra-coach/env NÃO EXISTE"
    all_ok=false
  fi

  # Diretórios
  for dir in "$DATA_DIR" "$DATA_DIR/logs" "$DATA_DIR/exports" "$DATA_DIR/backups"; do
    if [[ -d "$dir" ]]; then
      log_success "$dir existe"
    else
      log_warn "$dir NÃO EXISTE (criando...)"
      mkdir -p "$dir"
    fi
  done

  echo ""
  if [[ "$all_ok" == true ]]; then
    log_success "Todos os pré-requisitos OK!"
    return 0
  else
    log_error "Alguns pré-requisitos faltando. Verifique acima."
    return 1
  fi
}

cmd_init_db() {
  echo "🗄️  Inicializando database..."
  echo ""

  if [[ -f "$DB" ]]; then
    log_warn "Database já existe: $DB"
    read -p "Recriar do zero? (APAGA TODOS OS DADOS) [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      log_info "Operação cancelada"
      return 0
    fi

    # Backup antes de reset
    backup_file="$DATA_DIR/backups/coach_backup_$(date +%Y%m%d_%H%M%S).sqlite"
    cp "$DB" "$backup_file"
    log_success "Backup criado: $backup_file"
  fi

  "$PROJECT_DIR/bin/init_db.sh" --reset
  log_success "Database inicializado!"
}

cmd_create_athlete() {
  echo "👤 Criando atleta de teste: $TEST_ATHLETE"
  echo ""

  sqlite3 "$DB" <<EOF
INSERT OR REPLACE INTO athlete_profile (
  athlete_id, hr_max, hr_rest, goal_event
)
VALUES (
  '$TEST_ATHLETE', 185, 48, 'Ultra 12h E2E Test 2026-06-15'
);

INSERT OR REPLACE INTO athlete_state (
  athlete_id, coach_mode,
  readiness_score, fatigue_score, monotony, strain,
  weekly_load, weekly_distance_km, weekly_time_min,
  last_quality_at, last_long_run_at
)
VALUES (
  '$TEST_ATHLETE', 'moderate',
  75.0, 50.0, 1.2, 85.0,
  100.0, 60.0, 300.0,
  date('now', '-3 days'), date('now', '-6 days')
);
EOF

  log_success "Atleta criado: $TEST_ATHLETE"
  log_info "HR max: 185, HR rest: 48"
  log_info "Readiness: 75, Fatigue: 50"
}

cmd_insert_test_data() {
  echo "📊 Inserindo dados de teste..."
  echo ""

  sqlite3 "$DB" <<EOF
-- Limpar sessões antigas do atleta de teste
DELETE FROM session_log WHERE athlete_id = '$TEST_ATHLETE';

-- Inserir 4 sessões variadas
INSERT INTO session_log (
  athlete_id, start_at, duration_min, distance_km, avg_hr, trimp, tags, notes
)
VALUES
  ('$TEST_ATHLETE', datetime('now', '-7 days', 'start of day', '+8 hours'), 60, 10.0, 145, 85.5, 'easy', 'Easy recovery run'),
  ('$TEST_ATHLETE', datetime('now', '-5 days', 'start of day', '+8 hours'), 75, 12.0, 165, 135.2, 'quality', 'Intervals 6x5min Z3'),
  ('$TEST_ATHLETE', datetime('now', '-3 days', 'start of day', '+8 hours'), 120, 20.0, 152, 168.4, 'long', 'Long run weekend'),
  ('$TEST_ATHLETE', datetime('now', '-1 days', 'start of day', '+8 hours'), 45, 7.5, 142, 58.3, 'easy', 'Short recovery');
EOF

  log_success "4 sessões inseridas"

  # Verificar weekly_state
  local count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM weekly_state WHERE athlete_id='$TEST_ATHLETE';")
  log_info "Weekly state: $count registro(s) criado(s) pelo trigger"
}

cmd_run_dry() {
  echo "🧪 Executando coach em modo dry-run..."
  echo ""

  ATHLETE="$TEST_ATHLETE" "$PROJECT_DIR/bin/run_coach_daily.sh" --dry-run --verbose
}

cmd_run_real() {
  echo "🤖 Executando coach com chamada REAL à OpenAI..."
  echo ""

  log_warn "⚠️  Esta operação consome créditos da API OpenAI!"
  read -p "Continuar? [y/N]: " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_info "Operação cancelada"
    return 0
  fi

  # Limpar plano de hoje se existir
  sqlite3 "$DB" <<EOF
DELETE FROM daily_plan WHERE athlete_id='$TEST_ATHLETE' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='$TEST_ATHLETE' AND plan_date=date('now');
EOF

  ATHLETE="$TEST_ATHLETE" "$PROJECT_DIR/bin/run_coach_daily.sh" --verbose
}

cmd_show_workout() {
  echo "📋 Workout do dia:"
  echo ""

  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  dp.plan_date,
  dp.workout_type,
  dpa.status,
  json_extract(dpa.ai_workout_json, '$.workout_title') as title
FROM daily_plan dp
LEFT JOIN daily_plan_ai dpa ON dp.athlete_id = dpa.athlete_id AND dp.plan_date = dpa.plan_date
WHERE dp.athlete_id = '$TEST_ATHLETE'
ORDER BY dp.plan_date DESC
LIMIT 1;
EOF

  echo ""
  echo "JSON completo:"
  sqlite3 "$DB" "SELECT json(ai_workout_json) FROM daily_plan_ai WHERE athlete_id='$TEST_ATHLETE' ORDER BY plan_date DESC LIMIT 1;" | jq -C . 2>/dev/null || echo "(Nenhum workout gerado)"
}

cmd_show_state() {
  echo "📊 Estado do atleta: $TEST_ATHLETE"
  echo ""

  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  readiness_score,
  fatigue_score,
  monotony,
  strain,
  weekly_load,
  weekly_distance_km,
  last_quality_at,
  last_long_run_at,
  coach_mode
FROM athlete_state
WHERE athlete_id = '$TEST_ATHLETE';
EOF

  echo ""
  echo "Weekly State:"
  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  week_start,
  quality_days,
  long_days,
  total_time_min,
  ROUND(total_load, 1) as total_load,
  ROUND(total_distance_km, 1) as total_distance_km
FROM weekly_state
WHERE athlete_id = '$TEST_ATHLETE'
ORDER BY week_start DESC
LIMIT 3;
EOF
}

cmd_show_history() {
  echo "📜 Histórico de sessões: $TEST_ATHLETE"
  echo ""

  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  date(start_at) as session_date,
  duration_min,
  distance_km,
  avg_hr,
  tags,
  ROUND(trimp, 1) as trimp
FROM session_log
WHERE athlete_id = '$TEST_ATHLETE'
ORDER BY start_at DESC
LIMIT 10;
EOF
}

cmd_cleanup() {
  echo "🧹 Limpando dados de teste..."
  echo ""

  read -p "Deletar todos os dados do atleta '$TEST_ATHLETE'? [y/N]: " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_info "Operação cancelada"
    return 0
  fi

  sqlite3 "$DB" <<EOF
DELETE FROM session_log WHERE athlete_id = '$TEST_ATHLETE';
DELETE FROM daily_plan WHERE athlete_id = '$TEST_ATHLETE';
DELETE FROM daily_plan_ai WHERE athlete_id = '$TEST_ATHLETE';
DELETE FROM weekly_state WHERE athlete_id = '$TEST_ATHLETE';
DELETE FROM athlete_state WHERE athlete_id = '$TEST_ATHLETE';
DELETE FROM athlete_profile WHERE athlete_id = '$TEST_ATHLETE';
EOF

  log_success "Dados de teste deletados"
}

cmd_help() {
  cat <<EOF
Ultra Coach E2E Test Helper

Uso: $(basename "$0") <comando> [opções]

Comandos disponíveis:

  check         Verifica pré-requisitos (deps, config, diretórios)
  init          Inicializa database (com opção de reset)
  athlete       Cria atleta de teste
  data          Insere sessões de teste
  dry           Roda coach em modo dry-run
  run           Roda coach com chamada real à OpenAI
  workout       Mostra workout gerado para hoje
  state         Mostra estado atual do atleta
  history       Mostra histórico de sessões
  cleanup       Remove todos os dados do atleta de teste
  help          Mostra esta ajuda

Exemplos:

  # Setup inicial
  $(basename "$0") check
  $(basename "$0") init
  $(basename "$0") athlete
  $(basename "$0") data

  # Testar geração de treino
  $(basename "$0") dry
  $(basename "$0") run

  # Ver resultados
  $(basename "$0") workout
  $(basename "$0") state

  # Limpar
  $(basename "$0") cleanup

Variáveis de ambiente:
  TEST_ATHLETE      Nome do atleta de teste (default: test_e2e)
  ULTRA_COACH_DB    Path para o database (default: /var/lib/ultra-coach/coach.sqlite)

EOF
}

# Main
main() {
  local command="${1:-help}"

  case "$command" in
    check)
      cmd_check_prereqs
      ;;
    init)
      cmd_init_db
      ;;
    athlete)
      cmd_create_athlete
      ;;
    data)
      cmd_insert_test_data
      ;;
    dry)
      cmd_run_dry
      ;;
    run)
      cmd_run_real
      ;;
    workout)
      cmd_show_workout
      ;;
    state)
      cmd_show_state
      ;;
    history)
      cmd_show_history
      ;;
    cleanup)
      cmd_cleanup
      ;;
    help|--help|-h)
      cmd_help
      ;;
    *)
      log_error "Comando desconhecido: $command"
      echo ""
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
