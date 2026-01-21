#!/bin/bash

# --- ULTRA COACH PATHS (injetado pelo migrator) ---
ULTRA_COACH_PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-/opt/ultra-coach}"
ULTRA_COACH_DATA_DIR="${ULTRA_COACH_DATA_DIR:-/var/lib/ultra-coach}"
ULTRA_COACH_DB="${ULTRA_COACH_DB:-/var/lib/ultra-coach/coach.sqlite}"
ULTRA_COACH_PROMPT_FILE="${ULTRA_COACH_PROMPT_FILE:-/opt/ultra-coach/templates/coach_prompt_ultra.txt}"
ULTRA_COACH_FIT_DIR="${ULTRA_COACH_FIT_DIR:-/opt/ultra-coach/fit}"
# -------------------------------------------------
set -euo pipefail

# ---------- Logging estruturado ----------
log_info()  { echo "[$(date -Iseconds)][push][INFO] $*"; }
log_warn()  { echo "[$(date -Iseconds)][push][WARN] $*" >&2; }
log_err()   { echo "[$(date -Iseconds)][push][ERR] $*" >&2; }

# shellcheck disable=SC1091
source /etc/ultra-coach/env 2>/dev/null || true
if command -v node >/dev/null 2>&1 && [ -f "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs" ]; then
  eval "$(node "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs")"
fi

DB="$ULTRA_COACH_DB"
ATHLETE="${ATHLETE:-zz}"
PLAN_DATE="$(date -I)"  # YYYY-MM-DD
WEBHOOK_URL="${WEBHOOK_URL:-https://n8n.zanardizz.uk/webhook/coach/inbox}"

# Mensagem (formatação Telegram Markdown) a partir do ai_workout_json já aceito
SQL="
WITH j AS (
  SELECT ai_workout_json AS w
  FROM daily_plan_ai
  WHERE athlete_id='$ATHLETE'
    AND plan_date = '$PLAN_DATE'
    AND status='accepted'
  LIMIT 1
),
seg AS (
  SELECT
    json_extract(value,'\$.name') AS name,
    json_extract(value,'\$.duration_min') AS dur,
    json_extract(value,'\$.intensity') AS inten,
    json_extract(value,'\$.details') AS details,
    json_each.key AS idx
  FROM j, json_each(j.w, '\$.segments')
),
alts AS (
  SELECT
    json_extract(value,'\$.when') AS wh,
    json_extract(value,'\$.swap') AS sw,
    json_each.key AS idx
  FROM j, json_each(j.w, '\$.alternatives')
),
checks AS (
  SELECT value AS txt, json_each.key AS idx
  FROM j, json_each(j.w, '\$.safety_checks')
)
SELECT
  '🏃‍♂️ *Treino do dia* (' || date('now','localtime') || ')' || char(10) ||
  '*' || json_extract(w,'\$.workout_title') || '*' || char(10) ||
  'Tipo: *' || upper(json_extract(w,'\$.workout_type')) || '*  |  Duração: *' || json_extract(w,'\$.total_duration_min') || ' min*' || char(10) || char(10) ||

  '🎯 Alvo' || char(10) ||
  '• ' || json_extract(w,'\$.targets.primary') || char(10) ||
  CASE WHEN json_extract(w,'\$.targets.secondary') IS NOT NULL AND json_extract(w,'\$.targets.secondary') <> ''
       THEN '• ' || json_extract(w,'\$.targets.secondary') || char(10)
       ELSE '' END
  || char(10) ||

  '🧩 Estrutura' || char(10) ||
  (SELECT group_concat('• ' || name || ': ' || dur || ' min — ' || inten || char(10) || '  ' || details, char(10))
   FROM seg ORDER BY CAST(idx AS INT)) || char(10) || char(10) ||

  '🥤 Combustível/Hidratação' || char(10) ||
  '• CHO: ' || json_extract(w,'\$.fuel_hydration.carbs_g_per_h') || ' g/h' || char(10) ||
  '• Líquidos: ' || json_extract(w,'\$.fuel_hydration.fluids_ml_per_h') || ' ml/h' || char(10) ||
  '• Sódio: ' || json_extract(w,'\$.fuel_hydration.sodium_mg_per_h') || ' mg/h' || char(10) ||
  '• ' || json_extract(w,'\$.fuel_hydration.notes') || char(10) || char(10) ||

  '🛑 Safety checks' || char(10) ||
  (SELECT group_concat('• ' || txt, char(10)) FROM checks ORDER BY CAST(idx AS INT)) || char(10) ||

  CASE WHEN (SELECT COUNT(1) FROM alts) > 0 THEN
    char(10) || '🔁 Alternativas' || char(10) ||
    (SELECT group_concat('• ' || wh || ': ' || sw, char(10)) FROM alts ORDER BY CAST(idx AS INT))
  ELSE '' END
AS message
FROM j;
"

MESSAGE="$(sqlite3 "$DB" "$SQL")"

# Fallback se ainda não existir treino aceito
if [ -z "${MESSAGE:-}" ]; then
  MESSAGE="Sem treino IA aceito para hoje (${PLAN_DATE}). Rode o pipeline de geração/validação primeiro."
fi

# Envia para o n8n (que salva no Data Table e manda no Telegram)
jq -n \
  --arg athlete_id "$ATHLETE" \
  --arg plan_date "$PLAN_DATE" \
  --arg message "$MESSAGE" \
  '{athlete_id:$athlete_id, plan_date:$plan_date, message:$message}' \
| curl -sS -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    --data-binary @- >/dev/null
