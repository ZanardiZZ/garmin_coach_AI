#!/bin/bash

# --- ULTRA COACH PATHS (injetado pelo migrator) ---
ULTRA_COACH_PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-/opt/ultra-coach}"
ULTRA_COACH_DATA_DIR="${ULTRA_COACH_DATA_DIR:-/var/lib/ultra-coach}"
ULTRA_COACH_DB="${ULTRA_COACH_DB:-/var/lib/ultra-coach/coach.sqlite}"
ULTRA_COACH_PROMPT_FILE="${ULTRA_COACH_PROMPT_FILE:-/opt/ultra-coach/templates/coach_prompt_ultra.txt}"
ULTRA_COACH_FIT_DIR="${ULTRA_COACH_FIT_DIR:-/opt/ultra-coach/fit}"
# -------------------------------------------------
set -euo pipefail

# ---------- Argumentos ----------
DRY_RUN=0
VERBOSE=0

usage() {
  cat <<EOF
Uso: $(basename "$0") [opções]

Opções:
  --dry-run     Simula execução sem chamar OpenAI ou modificar banco
  --verbose     Mostra informações detalhadas
  -h, --help    Mostra esta ajuda
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=1; shift ;;
    --verbose)  VERBOSE=1; shift ;;
    -h|--help)  usage ;;
    *) echo "Opção desconhecida: $1"; usage ;;
  esac
done

# ---------- Logging estruturado ----------
log_info()  { echo "[$(date -Iseconds)][INFO] $*"; }
log_warn()  { echo "[$(date -Iseconds)][WARN] $*" >&2; }
log_err()   { echo "[$(date -Iseconds)][ERR] $*" >&2; }

# Rejeita plano com motivo registrado
reject_plan() {
  local reason="$1"
  local safe_reason="${reason//\'/\'\'}"  # escapa aspas simples
  sqlite3 "$DB" "UPDATE daily_plan_ai SET status='rejected', rejection_reason='$safe_reason', updated_at=datetime('now') WHERE athlete_id='$ATHLETE' AND plan_date='$PLAN_DATE';"
  log_err "$reason"
}

# Backup do banco antes de operacoes criticas
backup_db() {
  local backup_script="$ULTRA_COACH_PROJECT_DIR/bin/backup_db.sh"

  if [[ -x "$backup_script" ]]; then
    log_info "Criando backup do banco..."
    if "$backup_script" --quiet --keep 7; then
      log_info "Backup concluido"
    else
      log_warn "Falha no backup (continuando mesmo assim)"
    fi
  else
    [[ "$VERBOSE" -eq 1 ]] && log_info "Script de backup nao encontrado (pulando)"
  fi
}

# Retry com exponential backoff
# Uso: retry_curl <max_tentativas> <arquivo_saida> <curl_args...>
retry_curl() {
  local max_attempts="$1"
  local output_file="$2"
  shift 2

  local attempt=1
  local wait_time=2
  local http_code

  while [ $attempt -le $max_attempts ]; do
    http_code=$(curl -sS -w "%{http_code}" -o "$output_file" "$@")

    # Sucesso ou erro de cliente (4xx) - não faz retry
    if [[ "$http_code" =~ ^2 ]] || [[ "$http_code" =~ ^4 ]]; then
      echo "$http_code"
      return 0
    fi

    # Erro de servidor (5xx) ou rede - faz retry
    if [ $attempt -lt $max_attempts ]; then
      log_warn "Tentativa $attempt/$max_attempts falhou (HTTP $http_code). Aguardando ${wait_time}s..."
      sleep $wait_time
      wait_time=$((wait_time * 2))  # exponential backoff
    fi

    attempt=$((attempt + 1))
  done

  echo "$http_code"
  return 1
}

DB="$ULTRA_COACH_DB"
ATHLETE="${ATHLETE:-zz}"
MODEL="${MODEL:-gpt-5}"
PLAN_DATE="$(date -I)"
# carrega env central (tokens e paths)
source /etc/ultra-coach/env 2>/dev/null || true
if command -v node >/dev/null 2>&1 && [ -f "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs" ]; then
  eval "$(node "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs")"
fi

# sincroniza do Influx v1.1 -> SQLite (não mata o coach se falhar)
if [ "$DRY_RUN" = "1" ]; then
  log_info "[DRY-RUN] Pulando sync do InfluxDB"
else
  ATHLETE_ID="$ATHLETE" \
    /opt/ultra-coach/bin/sync_influx_to_sqlite.sh || true
fi
# Coloque sua chave aqui OU exporte no ambiente do shell/cron.
: "${OPENAI_API_KEY:=}"
if [ -z "$OPENAI_API_KEY" ]; then
  log_err " OPENAI_API_KEY não definido."
  exit 1
fi

# Cria diretório temporário seguro e garante limpeza ao sair
TMPDIR=$(mktemp -d -t ultra-coach.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# Arquivos temporários
TMP_COACH_BODY="$TMPDIR/coach_body.json"
TMP_COACH_RESP="$TMPDIR/coach_resp.json"
TMP_WORKOUT="$TMPDIR/workout.json"
TMP_WORKOUT_COMPACT="$TMPDIR/workout.compact.json"
TMP_FIT_OUT="$TMPDIR/workout_${PLAN_DATE}.fit"
TMP_CONSTRAINTS_MINI="$TMPDIR/constraints.json"

# Backup antes de operacoes criticas
if [ "$DRY_RUN" = "0" ]; then
  backup_db
fi

# 1) Recalcula athlete_state (baseado nos últimos 7/28 dias)
sqlite3 "$DB" <<SQL
WITH last7 AS (
  SELECT
    athlete_id,
    SUM(COALESCE(trimp,0)) AS load7,
    SUM(COALESCE(distance_km,0)) AS dist7,
    SUM(COALESCE(duration_min,0)) AS time7
  FROM session_log
  WHERE athlete_id='$ATHLETE'
    AND datetime(start_at) >= datetime('now','-7 days')
),
last28_days AS (
  SELECT athlete_id, date(start_at) AS d, SUM(COALESCE(trimp,0)) AS day_load
  FROM session_log
  WHERE athlete_id='$ATHLETE'
    AND datetime(start_at) >= datetime('now','-28 days')
  GROUP BY athlete_id, date(start_at)
),
last28 AS (
  SELECT athlete_id,
         AVG(day_load) AS avg_day,
         CASE WHEN AVG(day_load)=0 THEN 0 ELSE (MAX(day_load) / AVG(day_load)) END AS monotony
  FROM last28_days
),
last_long AS (
  SELECT athlete_id,
         MAX(distance_km) AS last_long_km,
         MAX(start_at) AS last_long_at
  FROM session_log
  WHERE athlete_id='$ATHLETE'
    AND (tags LIKE '%long%' OR distance_km >= 18)
),
last_quality AS (
  SELECT athlete_id, MAX(start_at) AS last_quality_at
  FROM session_log
  WHERE athlete_id='$ATHLETE'
    AND (tags LIKE '%quality%')
)
INSERT INTO athlete_state
(athlete_id, readiness_score, fatigue_score, monotony, strain, weekly_load, weekly_distance_km, weekly_time_min,
 last_long_run_km, last_long_run_at, last_quality_at, updated_at)
VALUES
(
  '$ATHLETE',
  MAX(0, MIN(100, 85 - COALESCE((SELECT load7 FROM last7),0)*0.8 - COALESCE((SELECT monotony FROM last28),0)*10 )),
  MAX(0, MIN(100, COALESCE((SELECT load7 FROM last7),0)*1.2 + COALESCE((SELECT monotony FROM last28),0)*15 )),
  COALESCE((SELECT monotony FROM last28), 0),
  COALESCE((SELECT monotony FROM last28),0) * COALESCE((SELECT load7 FROM last7),0),
  COALESCE((SELECT load7 FROM last7),0),
  COALESCE((SELECT dist7 FROM last7),0),
  COALESCE((SELECT time7 FROM last7),0),
  COALESCE((SELECT last_long_km FROM last_long),0),
  (SELECT last_long_at FROM last_long),
  (SELECT last_quality_at FROM last_quality),
  datetime('now')
)
ON CONFLICT(athlete_id) DO UPDATE SET
  readiness_score=excluded.readiness_score,
  fatigue_score=excluded.fatigue_score,
  monotony=excluded.monotony,
  strain=excluded.strain,
  weekly_load=excluded.weekly_load,
  weekly_distance_km=excluded.weekly_distance_km,
  weekly_time_min=excluded.weekly_time_min,
  last_long_run_km=excluded.last_long_run_km,
  last_long_run_at=excluded.last_long_run_at,
  last_quality_at=excluded.last_quality_at,
  updated_at=datetime('now');
SQL
# 2) Gera/atualiza daily_plan do dia (determinístico com histórico)
sqlite3 "$DB" <<SQL
INSERT OR REPLACE INTO daily_plan
(athlete_id, plan_date, workout_type, prescription, readiness, fatigue, coach_mode, created_at, updated_at)
WITH base AS (
  SELECT
    st.athlete_id,
    st.coach_mode,
    st.readiness_score AS readiness,
    st.fatigue_score   AS fatigue,
    p.hr_max
  FROM athlete_state st
  JOIN athlete_profile p ON p.athlete_id = st.athlete_id
  WHERE st.athlete_id='$ATHLETE'
),
pol AS (
  SELECT
    b.*,
    cp.readiness_floor,
    cp.fatigue_cap,
    -- orçamentos semanais por modo (pode ajustar depois)
    CASE WHEN b.coach_mode='aggressive' THEN 2 ELSE 1 END AS max_quality_week,
    1 AS max_long_week
  FROM base b
  JOIN coach_policy cp ON cp.mode = b.coach_mode
),
wk AS (
  SELECT
    ws.quality_days,
    ws.long_days,
    ws.total_time_min,
    ws.total_load
  FROM weekly_state ws
  WHERE ws.athlete_id='$ATHLETE'
    AND ws.week_start = date('now','localtime','weekday 1','-7 days')
),
hist AS (
  SELECT
    pol.*,
    COALESCE(wk.quality_days,0) AS quality_days_wk,
    COALESCE(wk.long_days,0)    AS long_days_wk,
    COALESCE(wk.total_time_min,0) AS total_time_wk,
    COALESCE(wk.total_load,0) AS total_load_wk,
    CAST(strftime('%w','now','localtime') AS INT) AS dow
  FROM pol
  LEFT JOIN wk ON 1=1
),
decision AS (
  SELECT
    athlete_id,
    '$PLAN_DATE' AS plan_date,
    coach_mode,
    readiness,
    fatigue,

    CASE
      -- 1) Se estado ruim, não inventa: recovery
      WHEN readiness < readiness_floor OR fatigue > fatigue_cap THEN 'recovery'

      -- 2) Longão no fim de semana se ainda não fez long na semana
      WHEN dow IN (0,6) AND long_days_wk < max_long_week THEN 'long'

      -- 3) Quality em ter/qui se ainda não fez quality na semana
      WHEN dow IN (2,4) AND quality_days_wk < max_quality_week THEN 'quality'

      -- 4) Caso contrário: easy
      ELSE 'easy'
    END AS workout_type,

    'auto_weekly' AS prescription
  FROM hist
)
SELECT
  athlete_id, plan_date, workout_type, prescription, readiness, fatigue, coach_mode,
  datetime('now'), datetime('now')
FROM decision;
SQL


# 3) Gera/atualiza constraints do dia em daily_plan_ai (ultra-friendly)
sqlite3 "$DB" <<SQL
INSERT OR REPLACE INTO daily_plan_ai
(athlete_id, plan_date, allowed_type, constraints_json, ai_workout_json, ai_model, status, created_at, updated_at)
WITH wk AS (
  SELECT
    COALESCE(quality_days,0) AS quality_days,
    COALESCE(long_days,0) AS long_days,
    COALESCE(total_time_min,0) AS total_time_min,
    COALESCE(total_load,0) AS total_load
  FROM weekly_state
  WHERE athlete_id='$ATHLETE'
    AND week_start = date('now','localtime','weekday 1','-7 days')
),
fb AS (
  SELECT
    group_concat(
      COALESCE(session_date, date(created_at)) || ' ' ||
      COALESCE(perceived,'') || ' rpe=' || COALESCE(rpe,'') || ' ' ||
      COALESCE(conditions,'') || ' ' || COALESCE(notes,''),
      ' | '
    ) AS feedback_recent
  FROM athlete_feedback
  WHERE athlete_id='$ATHLETE'
    AND date(created_at) >= date('now','localtime','-7 days')
),
mode_budget AS (
  SELECT
    dp.athlete_id,
    dp.plan_date,
    dp.workout_type,
    dp.coach_mode,
    dp.readiness,
    dp.fatigue,
    ap.hr_max,
    ap.goal_event,
    CASE WHEN dp.coach_mode='aggressive' THEN 2 ELSE 1 END AS max_quality_week,
    1 AS max_long_week,
    wk.quality_days AS quality_days_wk,
    wk.long_days AS long_days_wk,
    wk.total_time_min AS total_time_wk,
    wk.total_load AS total_load_wk,
    fb.feedback_recent AS feedback_recent
  FROM daily_plan dp
  JOIN athlete_profile ap ON ap.athlete_id = dp.athlete_id
  LEFT JOIN wk ON 1=1
  LEFT JOIN fb ON 1=1
  WHERE dp.athlete_id='$ATHLETE'
    AND dp.plan_date = '$PLAN_DATE'
)
SELECT
  athlete_id,
  plan_date,
  workout_type,
  json_object(
    'allowed_type', workout_type,
    'mode', coach_mode,
    'readiness', readiness,
    'fatigue', fatigue,

    'week_quality_used', quality_days_wk,
    'week_quality_max',  max_quality_week,
    'week_long_used',    long_days_wk,
    'week_long_max',     max_long_week,
    'week_total_time_min', total_time_wk,
    'week_total_load',     total_load_wk,
    'feedback_recent', COALESCE(feedback_recent, ''),

    'z2_hr_cap', CAST(ROUND(hr_max * 0.75) AS INT),
    'z3_hr_floor', CAST(ROUND(hr_max * 0.80) AS INT),

    'duration_min', CASE workout_type
  WHEN 'recovery' THEN 20
  WHEN 'easy' THEN 60
  WHEN 'quality' THEN 60
  WHEN 'long' THEN
    CASE
      WHEN CAST(strftime('%w','now','localtime') AS INT) = 6 THEN 150  -- sábado main
      WHEN CAST(strftime('%w','now','localtime') AS INT) = 0 THEN 90   -- domingo secondary
      ELSE 120
    END
  ELSE 45 END,

'duration_max', CASE workout_type
  WHEN 'recovery' THEN 45
  WHEN 'easy' THEN 90
  WHEN 'quality' THEN 95
  WHEN 'long' THEN
    CASE
      WHEN CAST(strftime('%w','now','localtime') AS INT) = 6 THEN 240  -- sábado main
      WHEN CAST(strftime('%w','now','localtime') AS INT) = 0 THEN 150  -- domingo secondary
      ELSE 240
    END
  ELSE 90 END,

    'hard_minutes_cap', CASE workout_type
      WHEN 'quality' THEN 35
      WHEN 'long' THEN 15
      ELSE 0 END,
	'day_of_week', CAST(strftime('%w','now','localtime') AS INT),

	'back_to_back_day', CASE
  WHEN workout_type <> 'long' THEN 0
  WHEN CAST(strftime('%w','now','localtime') AS INT) = 6 THEN 1
  WHEN CAST(strftime('%w','now','localtime') AS INT) = 0 THEN 2
  ELSE 0 END,

	'long_role', CASE
  WHEN workout_type <> 'long' THEN NULL
  WHEN CAST(strftime('%w','now','localtime') AS INT) = 6 THEN 'main'
  WHEN CAST(strftime('%w','now','localtime') AS INT) = 0 THEN 'secondary'
  ELSE 'single' END,
    
	'goal', goal_event,
    'notes', 'Ultra weekly-aware. IA deve respeitar tipo e caps; sugerir variações apropriadas.'
  ),
  NULL,
  NULL,
  'pending',
  datetime('now'),
  datetime('now')
FROM mode_budget;
SQL


# Se já tem accepted do dia, não sobrescreve (idempotente)
STATUS=$(sqlite3 "$DB" "SELECT status FROM daily_plan_ai WHERE athlete_id='$ATHLETE' AND plan_date='$PLAN_DATE' LIMIT 1;")
if [ "$STATUS" = "accepted" ]; then
  /usr/local/bin/push_coach_message.sh
  exit 0
fi

# 4) Chama OpenAI com constraints
CONSTRAINTS_RAW=$(sqlite3 "$DB" "SELECT constraints_json FROM daily_plan_ai WHERE athlete_id='$ATHLETE' AND plan_date='$PLAN_DATE' LIMIT 1;")
if [ -z "${CONSTRAINTS_RAW:-}" ] || [ "${CONSTRAINTS_RAW:-}" = "null" ]; then
  log_err " constraints_json vazio/null para o dia. daily_plan_ai não foi gerado?"
  exit 2
fi

jq -n \
  --arg constraints "$CONSTRAINTS_RAW" \
  --rawfile prompt $ULTRA_COACH_PROMPT_FILE \
  '{
    model: "'"$MODEL"'",
    input: [
      {role:"system", content:"Você é um treinador de corrida focado em ultra (12h / ~90km). Responda apenas com JSON válido, sem texto extra."},
      {role:"user", content: ($prompt + "\n\nCONSTRAINTS_JSON:\n" + $constraints)}
    ]
  }' > "$TMP_COACH_BODY"

jq -e . "$TMP_COACH_BODY" >/dev/null || { log_err " coach_body.json inválido"; exit 2; }

# Modo dry-run: mostra o que seria enviado e sai
if [ "$DRY_RUN" = "1" ]; then
  log_info "[DRY-RUN] Constraints do dia:"
  echo "$CONSTRAINTS_RAW" | jq .
  log_info "[DRY-RUN] Payload que seria enviado à OpenAI:"
  jq . "$TMP_COACH_BODY"
  log_info "[DRY-RUN] Finalizando sem chamar OpenAI"
  exit 0
fi

# Chama OpenAI com retry (3 tentativas, exponential backoff)
HTTP_CODE=$(retry_curl 3 "$TMP_COACH_RESP" \
  https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d @"$TMP_COACH_BODY")

# Verifica código HTTP
if [ "$HTTP_CODE" != "200" ]; then
  ERROR_MSG=$(jq -r '.error.message // "Erro desconhecido"' "$TMP_COACH_RESP" 2>/dev/null || echo "Erro desconhecido")
  reject_plan "OpenAI retornou HTTP $HTTP_CODE: $ERROR_MSG"
  exit 2
fi

# 5) Extrai texto JSON do output e valida
WORKOUT_JSON=$(jq -r '(
  .output[]?
  | select(.type=="message")
  | .content[]?
  | select(.type=="output_text")
  | .text
) // empty' "$TMP_COACH_RESP")

if [ -z "$WORKOUT_JSON" ]; then
  reject_plan "Não consegui extrair workout_json da resposta OpenAI"
  exit 2
fi

echo "$WORKOUT_JSON" > "$TMP_WORKOUT"
jq -c . "$TMP_WORKOUT" > "$TMP_WORKOUT_COMPACT"

# Valida contra constraints
ALLOWED_TYPE=$(echo "$CONSTRAINTS_RAW" | jq -r '.allowed_type')
DUR_MIN=$(echo "$CONSTRAINTS_RAW" | jq -r '.duration_min')
DUR_MAX=$(echo "$CONSTRAINTS_RAW" | jq -r '.duration_max')
HARD_CAP=$(echo "$CONSTRAINTS_RAW" | jq -r '.hard_minutes_cap')

jq -e --arg at "$ALLOWED_TYPE" --argjson dmin "$DUR_MIN" --argjson dmax "$DUR_MAX" '
  (.workout_type == $at)
  and (.total_duration_min >= $dmin and .total_duration_min <= $dmax)
  and (.segments | type=="array" and length>=2)
' "$TMP_WORKOUT" >/dev/null || {
  reject_plan "Validação básica falhou: tipo/duração/segments inválidos"
  exit 3
}

if [ "$HARD_CAP" = "0" ]; then
  # 1) Proíbe Z3/Z4/tiro/threshold/VO2 explícitos
  if jq -r '.. | strings' $TMP_WORKOUT | grep -Eiq '(z3|z4|tiro|threshold|limiar|vo2|maximal|all-out)'; then
    reject_plan "hard_cap=0 mas detectei intensidade proibida (Z3/Z4/tiro/threshold/VO2)"
    exit 4
  fi

  # 2) Verifica intensities declaradas nos segmentos (estrutura)
  if jq -r '.segments[]?.intensity // ""' $TMP_WORKOUT | grep -Eiq '(z3|z4|forte|duro|intenso|limiar|vo2)'; then
    reject_plan "hard_cap=0 mas segment.intensity sugere esforço proibido"
    exit 4
  fi

  # 3) Permite a palavra "intervalo" se for só descanso/caminhada; mas proíbe se vier com repetições tipo 10x, 6x etc
  if jq -r '.. | strings' $TMP_WORKOUT | grep -Eiq '([0-9]{1,2}\s*[xX]\s*[0-9]{2,4})'; then
    reject_plan "hard_cap=0 mas detectei padrão de repetição (ex.: 10x1000) típico de treino duro"
    exit 4
  fi
fi


# 6) Salva JSON aceito no SQLite via readfile()
sqlite3 "$DB" <<SQL
UPDATE daily_plan_ai
SET ai_workout_json = json((SELECT readfile('$TMP_WORKOUT_COMPACT'))),
    ai_model = '$MODEL',
    status = 'accepted',
    updated_at = datetime('now')
WHERE athlete_id = '$ATHLETE'
  AND plan_date = '$PLAN_DATE';
SQL

# 6.5) (Opcional) Gera arquivo .FIT do treino e envia no Telegram como documento.
#
# Pré-requisitos:
# - Node.js + npm instalados
# - Conversor instalado em $ULTRA_COACH_FIT_DIR/workout_to_fit.mjs
#   (com dependências via: cd $ULTRA_COACH_FIT_DIR && npm install)
# - Para enviar o anexo no Telegram sem depender do push_coach_message.sh:
#   export TELEGRAM_BOT_TOKEN="..."  e  export TELEGRAM_CHAT_ID="..."
#
# Observação: se algo falhar aqui, o script NÃO aborta (só loga),
# porque o texto do treino já vai ser enviado pelo push_coach_message.sh.

FIT_OUT="$TMP_FIT_OUT"
CONSTRAINTS_MINI_JSON="$TMP_CONSTRAINTS_MINI"

if command -v node >/dev/null 2>&1 && [ -f $ULTRA_COACH_FIT_DIR/workout_to_fit.mjs ]; then
  # cria um constraints mínimo (cap de FC e floors)
  echo "$CONSTRAINTS_RAW" | jq '{z2_hr_cap, z3_hr_floor}' > "$CONSTRAINTS_MINI_JSON" || true

  if node $ULTRA_COACH_FIT_DIR/workout_to_fit.mjs \
      --in $TMP_WORKOUT_COMPACT \
      --out "$FIT_OUT" \
      --constraints "$CONSTRAINTS_MINI_JSON" >/dev/null 2>&1; then

    # Se você tiver token/chat_id no ambiente, envia o FIT como documento.
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
      TITLE=$(jq -r '.workout_title // "Treino"' $TMP_WORKOUT_COMPACT 2>/dev/null || echo "Treino")
      curl -sS \
        -F "chat_id=$TELEGRAM_CHAT_ID" \
        -F "caption=FIT do treino ($PLAN_DATE): $TITLE" \
        -F "document=@${FIT_OUT};type=application/octet-stream" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
        >/dev/null 2>&1 || log_warn " Falhei ao enviar FIT no Telegram (sendDocument)."
    else
      log_info " FIT gerado em $FIT_OUT (TELEGRAM_BOT_TOKEN/CHAT_ID não definidos, não enviei anexo)."
    fi
  else
    log_warn " Conversão para FIT falhou (node/workout_to_fit.mjs). Treino texto seguirá normalmente."
  fi
else
  log_info " FIT não gerado (node ausente ou $ULTRA_COACH_FIT_DIR/workout_to_fit.mjs não encontrado)."
fi

# 7) Envia para o n8n/Telegram
/usr/local/bin/push_coach_message.sh
