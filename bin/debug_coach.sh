#!/bin/bash
# debug_coach.sh - Diagnóstico do pipeline do coach

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✅${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠️${NC}  $*"; }
log_error() { echo -e "${RED}❌${NC} $*"; }

# Configurações
source /etc/ultra-coach/env 2>/dev/null || true
ATHLETE="${ATHLETE:-test_e2e}"
DB="${ULTRA_COACH_DB:-/var/lib/ultra-coach/coach.sqlite}"
TODAY=$(date +%Y-%m-%d)

echo "════════════════════════════════════════════════════════"
echo "  DIAGNÓSTICO DO COACH - Ultra Coach"
echo "════════════════════════════════════════════════════════"
echo ""
log_info "Atleta: $ATHLETE"
log_info "Data: $TODAY"
log_info "Database: $DB"
echo ""

# Verificação 1: Database existe?
echo "━━━ 1. DATABASE ━━━"
if [[ -f "$DB" ]]; then
  log_success "Database existe: $DB"

  # Integridade
  integrity=$(sqlite3 "$DB" "PRAGMA integrity_check;" 2>&1)
  if [[ "$integrity" == "ok" ]]; then
    log_success "Integridade OK"
  else
    log_error "Integridade comprometida: $integrity"
  fi
else
  log_error "Database NÃO existe: $DB"
  echo ""
  echo "Solução: ./bin/test_e2e_helper.sh init"
  exit 1
fi
echo ""

# Verificação 2: Atleta existe?
echo "━━━ 2. ATHLETE PROFILE ━━━"
athlete_exists=$(sqlite3 "$DB" "SELECT COUNT(*) FROM athlete_profile WHERE athlete_id='$ATHLETE';" 2>&1)

if [[ "$athlete_exists" == "1" ]]; then
  log_success "Atleta existe: $ATHLETE"

  # Mostrar dados
  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT athlete_id, hr_max, hr_rest, goal_event FROM athlete_profile WHERE athlete_id='$ATHLETE';
EOF
else
  log_error "Atleta NÃO existe: $ATHLETE"
  echo ""
  echo "Solução: ./bin/test_e2e_helper.sh athlete"
  exit 1
fi
echo ""

# Verificação 3: Athlete state existe?
echo "━━━ 3. ATHLETE STATE ━━━"
state_exists=$(sqlite3 "$DB" "SELECT COUNT(*) FROM athlete_state WHERE athlete_id='$ATHLETE';" 2>&1)

if [[ "$state_exists" == "1" ]]; then
  log_success "Athlete state existe"

  # Mostrar dados
  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  readiness_score,
  fatigue_score,
  coach_mode,
  monotony,
  strain,
  weekly_load,
  last_quality_at,
  last_long_run_at
FROM athlete_state
WHERE athlete_id='$ATHLETE';
EOF
else
  log_warn "Athlete state NÃO existe (será criado no primeiro run)"
fi
echo ""

# Verificação 4: Sessões existem?
echo "━━━ 4. SESSION LOG ━━━"
session_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM session_log WHERE athlete_id='$ATHLETE';" 2>&1)

if [[ "$session_count" -gt 0 ]]; then
  log_success "Sessões encontradas: $session_count"

  # Mostrar últimas 3
  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  date(start_at) as session_date,
  duration_min,
  distance_km,
  avg_hr,
  tags
FROM session_log
WHERE athlete_id='$ATHLETE'
ORDER BY start_at DESC
LIMIT 3;
EOF
else
  log_warn "Nenhuma sessão encontrada"
  echo ""
  echo "Sugestão: ./bin/test_e2e_helper.sh data"
fi
echo ""

# Verificação 5: Weekly state existe?
echo "━━━ 5. WEEKLY STATE ━━━"
weekly_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM weekly_state WHERE athlete_id='$ATHLETE';" 2>&1)

if [[ "$weekly_count" -gt 0 ]]; then
  log_success "Weekly state encontrado: $weekly_count registro(s)"

  # Mostrar
  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  week_start,
  quality_days,
  long_days,
  total_time_min,
  total_load,
  total_distance_km
FROM weekly_state
WHERE athlete_id='$ATHLETE'
ORDER BY week_start DESC
LIMIT 2;
EOF
else
  log_warn "Weekly state vazio (trigger deve criar no primeiro run)"
fi
echo ""

# Verificação 6: Plano de hoje existe?
echo "━━━ 6. DAILY PLAN (hoje: $TODAY) ━━━"
plan_exists=$(sqlite3 "$DB" "SELECT COUNT(*) FROM daily_plan WHERE athlete_id='$ATHLETE' AND plan_date='$TODAY';" 2>&1)

if [[ "$plan_exists" == "1" ]]; then
  log_success "Daily plan existe para hoje"

  # Mostrar
  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  plan_date,
  workout_type,
  prescription,
  readiness,
  fatigue,
  coach_mode,
  created_at
FROM daily_plan
WHERE athlete_id='$ATHLETE' AND plan_date='$TODAY';
EOF
else
  log_warn "Daily plan NÃO existe para hoje (será criado no run)"
fi
echo ""

# Verificação 7: Daily plan AI existe?
echo "━━━ 7. DAILY PLAN AI (hoje: $TODAY) ━━━"
plan_ai_exists=$(sqlite3 "$DB" "SELECT COUNT(*) FROM daily_plan_ai WHERE athlete_id='$ATHLETE' AND plan_date='$TODAY';" 2>&1)

if [[ "$plan_ai_exists" == "1" ]]; then
  log_success "Daily plan AI existe para hoje"

  # Mostrar
  sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT
  plan_date,
  status,
  CASE
    WHEN constraints_json IS NULL THEN 'NULL'
    WHEN constraints_json = '' THEN 'EMPTY'
    ELSE 'OK (' || length(constraints_json) || ' chars)'
  END as constraints,
  CASE
    WHEN ai_workout_json IS NULL THEN 'NULL'
    WHEN ai_workout_json = '' THEN 'EMPTY'
    ELSE 'OK (' || length(ai_workout_json) || ' chars)'
  END as workout,
  rejection_reason
FROM daily_plan_ai
WHERE athlete_id='$ATHLETE' AND plan_date='$TODAY';
EOF

  echo ""

  # Verificar se constraints_json está preenchido
  constraints_check=$(sqlite3 "$DB" "SELECT constraints_json FROM daily_plan_ai WHERE athlete_id='$ATHLETE' AND plan_date='$TODAY';" 2>&1)

  if [[ -z "$constraints_check" || "$constraints_check" == "null" ]]; then
    log_error "constraints_json está VAZIO/NULL!"
    echo ""
    echo "Este é o problema! O script não está gerando os constraints."
    echo ""
    echo "Possíveis causas:"
    echo "  1. Athlete state não existe ou está incompleto"
    echo "  2. Coach policy não existe"
    echo "  3. Erro na query SQL que gera constraints"
    echo ""
    echo "Vou verificar coach_policy..."
    echo ""

    policy_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM coach_policy;" 2>&1)
    if [[ "$policy_count" -gt 0 ]]; then
      log_success "Coach policies existem: $policy_count"
      sqlite3 "$DB" <<EOF
.mode column
.headers on
SELECT mode, readiness_floor, fatigue_cap, max_hard_days_week FROM coach_policy;
EOF
    else
      log_error "Coach policies NÃO existem!"
      echo "Solução: ./bin/init_db.sh --reset"
    fi
  else
    log_success "constraints_json está preenchido"
    echo ""
    echo "JSON Preview:"
    echo "$constraints_check" | jq -C . 2>/dev/null || echo "$constraints_check"
  fi
else
  log_warn "Daily plan AI NÃO existe para hoje (será criado no run)"
fi
echo ""

# Verificação 8: Verificar se consegue gerar constraints manualmente
echo "━━━ 8. TESTE DE GERAÇÃO DE CONSTRAINTS ━━━"

# Verificar se athlete_state existe para o teste
if [[ "$state_exists" == "1" ]]; then
  log_info "Tentando gerar constraints manualmente..."

  # Query simplificada para testar
  test_constraints=$(sqlite3 "$DB" <<EOF
SELECT json_object(
  'test', 'ok',
  'athlete_id', '$ATHLETE',
  'readiness', (SELECT readiness_score FROM athlete_state WHERE athlete_id='$ATHLETE'),
  'coach_mode', (SELECT coach_mode FROM athlete_state WHERE athlete_id='$ATHLETE')
);
EOF
)

  if [[ -n "$test_constraints" ]]; then
    log_success "Consegue gerar JSON básico"
    echo "$test_constraints" | jq -C . 2>/dev/null || echo "$test_constraints"
  else
    log_error "Falha ao gerar JSON de teste"
  fi
else
  log_warn "Pulando teste (athlete_state não existe)"
fi
echo ""

# Resumo e recomendações
echo "════════════════════════════════════════════════════════"
echo "  RESUMO"
echo "════════════════════════════════════════════════════════"
echo ""

# Decisão baseada nas verificações
if [[ "$athlete_exists" != "1" ]]; then
  log_error "PROBLEMA: Atleta não existe"
  echo "Solução: ./bin/test_e2e_helper.sh athlete"
elif [[ "$state_exists" != "1" ]]; then
  log_warn "AVISO: Athlete state não existe (será criado no run)"
  echo "Pode tentar: ATHLETE=$ATHLETE ./bin/run_coach_daily.sh --dry-run --verbose"
elif [[ "$session_count" == "0" ]]; then
  log_warn "AVISO: Sem sessões de treino"
  echo "Sugestão: ./bin/test_e2e_helper.sh data"
elif [[ "$plan_ai_exists" == "1" ]] && [[ -z "$constraints_check" || "$constraints_check" == "null" ]]; then
  log_error "PROBLEMA: daily_plan_ai existe mas constraints_json está vazio"
  echo ""
  echo "Soluções possíveis:"
  echo "  1. Deletar registros de hoje e retentar:"
  echo "     sqlite3 $DB \"DELETE FROM daily_plan WHERE athlete_id='$ATHLETE' AND plan_date='$TODAY';\""
  echo "     sqlite3 $DB \"DELETE FROM daily_plan_ai WHERE athlete_id='$ATHLETE' AND plan_date='$TODAY';\""
  echo "     ATHLETE=$ATHLETE ./bin/run_coach_daily.sh --dry-run --verbose"
  echo ""
  echo "  2. Verificar logs do último run:"
  echo "     tail -50 /var/lib/ultra-coach/logs/coach.log"
else
  log_success "Setup parece OK!"
  echo ""
  echo "Próximo passo:"
  echo "  ATHLETE=$ATHLETE ./bin/run_coach_daily.sh --dry-run --verbose"
fi
echo ""
echo "════════════════════════════════════════════════════════"
