#!/usr/bin/env bash
set -euo pipefail

ULTRA_COACH_PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-/opt/ultra-coach}"
ULTRA_COACH_DB="${ULTRA_COACH_DB:-/var/lib/ultra-coach/coach.sqlite}"

# shellcheck disable=SC1091
source /etc/ultra-coach/env 2>/dev/null || true
if command -v node >/dev/null 2>&1 && [ -f "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs" ]; then
  eval "$(node "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs")"
fi

log_info() { echo "[$(date -Iseconds)][weekly][INFO] $*"; }
log_err() { echo "[$(date -Iseconds)][weekly][ERR] $*" >&2; }

DB="$ULTRA_COACH_DB"
ATHLETE="${ATHLETE:-zz}"

SEND_DAY="${WEEKLY_SUMMARY_DAY:-1}"   # 1=Mon .. 7=Sun
SEND_TIME="${WEEKLY_SUMMARY_TIME:-07:00}"
SEND_TZ="${WEEKLY_SUMMARY_TZ:-America/Sao_Paulo}"
LAST_SENT="${WEEKLY_SUMMARY_LAST_SENT:-}"

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  log_err "Telegram não configurado (TELEGRAM_BOT_TOKEN/CHAT_ID)."
  exit 1
fi

now_day="$(TZ="$SEND_TZ" date +%u)"
now_time="$(TZ="$SEND_TZ" date +%H:%M)"
if [[ "$now_day" != "$SEND_DAY" || "$now_time" != "$SEND_TIME" ]]; then
  exit 0
fi

today="$(TZ="$SEND_TZ" date +%F)"
dow="$(TZ="$SEND_TZ" date +%u)"
start_date="$(TZ="$SEND_TZ" date -d "$today -$((dow-1)) days" +%F)"
end_date="$(TZ="$SEND_TZ" date -d "$start_date +6 days" +%F)"

if [[ -n "$LAST_SENT" && "$LAST_SENT" == "$start_date" ]]; then
  exit 0
fi

rows="$(sqlite3 -separator '|' "$DB" "
SELECT
  dp.plan_date,
  dp.workout_type,
  dp.readiness,
  dp.fatigue,
  dai.status,
  json_extract(dai.ai_workout_json, '\$.workout_title'),
  json_extract(dai.ai_workout_json, '\$.total_duration_min')
FROM daily_plan dp
LEFT JOIN daily_plan_ai dai
  ON dai.athlete_id = dp.athlete_id AND dai.plan_date = dp.plan_date
WHERE dp.athlete_id = '$ATHLETE'
  AND dp.plan_date BETWEEN '$start_date' AND '$end_date'
ORDER BY dp.plan_date;
")"

recommend() {
  local readiness="$1"
  local fatigue="$2"
  readiness="${readiness:-0}"
  fatigue="${fatigue:-0}"
  if awk "BEGIN{exit !($readiness < 55 || $fatigue > 75)}"; then
    echo "abrandar"
  elif awk "BEGIN{exit !($readiness > 75 && $fatigue < 50)}"; then
    echo "puxar"
  else
    echo "seguir"
  fi
}

msg="Plano semanal (${start_date} a ${end_date})\n"
if [[ -z "$rows" ]]; then
  msg="${msg}\nSem plano registrado no periodo."
else
  while IFS='|' read -r plan_date workout_type readiness fatigue ai_status workout_title duration_min; do
    day_label="$(TZ="$SEND_TZ" date -d "$plan_date" +'%a %d/%m')"
    rec="$(recommend "$readiness" "$fatigue")"
    duration_label=""
    if [[ -n "$duration_min" && "$duration_min" != "null" ]]; then
      duration_label=" ${duration_min}min"
    fi
    title_label=""
    if [[ -n "$workout_title" && "$workout_title" != "null" ]]; then
      title_label=" - $workout_title"
    fi
    status_label=""
    if [[ -n "$ai_status" && "$ai_status" != "null" ]]; then
      status_label=" ($ai_status)"
    fi
    msg="${msg}\n${day_label}: ${workout_type}${duration_label}${status_label} | ${rec}${title_label}"
  done <<< "$rows"
fi

curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=$TELEGRAM_CHAT_ID" \
  --data-urlencode "text=$msg" >/dev/null

if command -v node >/dev/null 2>&1 && [ -f "$ULTRA_COACH_PROJECT_DIR/bin/config_set.mjs" ]; then
  node "$ULTRA_COACH_PROJECT_DIR/bin/config_set.mjs" WEEKLY_SUMMARY_LAST_SENT "$start_date" || true
fi

log_info "Resumo semanal enviado."
