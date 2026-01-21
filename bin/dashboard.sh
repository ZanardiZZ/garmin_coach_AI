#!/usr/bin/env bash
set -euo pipefail

# --- ULTRA COACH PATHS ---
ULTRA_COACH_PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-/opt/ultra-coach}"
ULTRA_COACH_DATA_DIR="${ULTRA_COACH_DATA_DIR:-/var/lib/ultra-coach}"
ULTRA_COACH_DB="${ULTRA_COACH_DB:-/var/lib/ultra-coach/coach.sqlite}"
# -------------------------------------------------

# shellcheck disable=SC1091
source /etc/ultra-coach/env 2>/dev/null || true

DB="$ULTRA_COACH_DB"
ATHLETE_ID="${ATHLETE:-zz}"

usage() {
  cat <<EOF
Uso: $(basename "$0") [opcoes]

Opcoes:
  --athlete-id <id>  Athlete ID (default: $ATHLETE_ID)
  -h, --help         Ajuda
EOF
  exit 0
}

log_err() { echo "[$(date -Iseconds)][dashboard][ERR] $*" >&2; }

sql_escape() {
  local val="$1"
  echo "${val//\'/\'\'}"
}

require_bin() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || { log_err "Falta dependencia: $bin"; exit 1; }
}

bar() {
  local value="$1"
  local max="${2:-100}"
  local width="${3:-20}"
  awk -v v="$value" -v m="$max" -v w="$width" '
    BEGIN{
      if (m <= 0) m = 100;
      if (v < 0) v = 0;
      if (v > m) v = m;
      fill = int((v / m) * w + 0.5);
      for (i = 0; i < fill; i++) printf "#";
      for (i = fill; i < w; i++) printf ".";
    }'
}

fmt_num() {
  local n="$1"
  local fmt="${2:-%.1f}"
  if [[ -z "$n" || "$n" == "null" ]]; then
    echo "n/a"
    return 0
  fi
  awk -v v="$n" -v f="$fmt" 'BEGIN{ printf f, v }'
}

fmt_minutes() {
  local min="$1"
  if [[ -z "$min" || "$min" == "null" ]]; then
    echo "n/a"
    return 0
  fi
  awk -v m="$min" '
    BEGIN{
      if (m < 0) { print "n/a"; exit; }
      h = int(m / 60);
      mm = int(m % 60 + 0.5);
      if (h > 0) printf "%dh %02dm", h, mm;
      else printf "%dm", mm;
    }'
}

require_bin sqlite3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --athlete-id) ATHLETE_ID="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) log_err "Opcao desconhecida: $1"; usage ;;
  esac
done

if [[ ! -f "$DB" ]]; then
  log_err "Banco nao encontrado: $DB"
  exit 1
fi

safe_athlete="$(sql_escape "$ATHLETE_ID")"

profile="$(sqlite3 -separator '|' "$DB" "SELECT athlete_id, name, goal_event FROM athlete_profile WHERE athlete_id='$safe_athlete' LIMIT 1;")"
if [[ -z "$profile" ]]; then
  log_err "Athlete nao encontrado: $ATHLETE_ID"
  exit 1
fi

IFS='|' read -r athlete_id name goal_event <<< "$profile"

state="$(sqlite3 -separator '|' "$DB" "SELECT readiness_score, fatigue_score, coach_mode FROM athlete_state WHERE athlete_id='$safe_athlete' LIMIT 1;")"
IFS='|' read -r readiness fatigue coach_mode <<< "${state:-||}"
readiness="${readiness:-0}"
fatigue="${fatigue:-0}"
coach_mode="${coach_mode:-n/a}"

weekly="$(sqlite3 -separator '|' "$DB" "SELECT quality_days, long_days, total_time_min, total_load, total_distance_km FROM weekly_state WHERE athlete_id='$safe_athlete' AND week_start=date('now','localtime','weekday 1','-7 days') LIMIT 1;")"
IFS='|' read -r q_days l_days w_time w_load w_dist <<< "${weekly:-0|0|0|0|0}"

last_act="$(sqlite3 -separator '|' "$DB" "SELECT start_at, distance_km, duration_min, avg_hr, tags FROM session_log WHERE athlete_id='$safe_athlete' ORDER BY start_at DESC LIMIT 1;")"
IFS='|' read -r last_at last_dist last_dur last_hr last_tags <<< "${last_act:-||||}"

today_plan="$(sqlite3 -separator '|' "$DB" "SELECT plan_date, workout_type, ai_status, duration_min, workout_title FROM v_today_plan WHERE athlete_id='$safe_athlete' LIMIT 1;")"
IFS='|' read -r plan_date workout_type ai_status duration_min workout_title <<< "${today_plan:-||||}"

compliance="$(sqlite3 -separator '|' "$DB" "SELECT COUNT(*), SUM(CASE WHEN status='accepted' THEN 1 ELSE 0 END), SUM(CASE WHEN status='rejected' THEN 1 ELSE 0 END) FROM daily_plan_ai WHERE athlete_id='$safe_athlete' AND plan_date >= date('now','localtime','-30 days');")"
IFS='|' read -r plan_total plan_ok plan_rej <<< "${compliance:-0|0|0}"

longs="$(sqlite3 -separator '|' "$DB" "SELECT start_at, distance_km FROM session_log WHERE athlete_id='$safe_athlete' AND tags LIKE '%long%' ORDER BY start_at DESC LIMIT 4;")"

today="$(date -I)"

echo "=============================="
echo "ULTRA COACH DASHBOARD"
echo "Athlete: $name ($athlete_id)"
echo "Goal: ${goal_event:-n/a}"
echo "Date: $today"
echo "=============================="
echo
echo "Estado Atual"
echo "  Readiness: $(fmt_num "$readiness" "%.0f")/100  $(bar "$readiness")"
echo "  Fatigue:   $(fmt_num "$fatigue" "%.0f")/100  $(bar "$fatigue")"
echo "  Coach:     $coach_mode"
echo
echo "Semana Atual"
echo "  Distancia: $(fmt_num "$w_dist" "%.1f") km"
echo "  Tempo:     $(fmt_minutes "$w_time")"
echo "  TRIMP:     $(fmt_num "$w_load" "%.0f")"
echo "  Quality:   ${q_days:-0}"
echo "  Long:      ${l_days:-0}"
echo
echo "Ultima Atividade"
if [[ -n "${last_at:-}" ]]; then
  echo "  Data:      $last_at"
  echo "  Distancia: $(fmt_num "$last_dist" "%.1f") km"
  echo "  Duracao:   $(fmt_minutes "$last_dur")"
  echo "  FC media:  $(fmt_num "$last_hr" "%.0f") bpm"
  echo "  Tags:      ${last_tags:-n/a}"
else
  echo "  n/a"
fi
echo
echo "Treino de Hoje"
if [[ -n "${plan_date:-}" ]]; then
  echo "  Tipo:      ${workout_type:-n/a}"
  echo "  Duracao:   $(fmt_num "$duration_min" "%.0f") min"
  echo "  Status IA: ${ai_status:-n/a}"
  echo "  Titulo:    ${workout_title:-n/a}"
else
  echo "  n/a"
fi
echo
echo "Planos IA (30 dias)"
echo "  Aceitos:   ${plan_ok:-0}/${plan_total:-0}"
echo "  Rejeitados:${plan_rej:-0}"
echo
echo "Long Runs (ultimos 4)"
if [[ -n "$longs" ]]; then
  while IFS='|' read -r d km; do
    echo "  - $d | $(fmt_num "$km" "%.1f") km"
  done <<< "$longs"
else
  echo "  n/a"
fi
