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
ATHLETE_DEFAULT="${ATHLETE:-zz}"

DRY_RUN=0
FORCE=0

usage() {
  cat <<EOF
Uso: $(basename "$0") [opcoes]

Opcoes:
  --athlete-id <id>        Athlete ID (default: $ATHLETE_DEFAULT)
  --name <nome>            Nome do atleta
  --hr-max <bpm>           FC max (obrigatorio)
  --hr-rest <bpm>          FC repouso (default: 50)
  --goal <texto>           Objetivo/evento
  --weekly-hours <horas>   Horas/semana alvo
  --coach-mode <modo>      conservative|moderate|aggressive (default: moderate)
  --force                 Atualiza se ja existir
  --dry-run               Mostra SQL sem gravar
  -h, --help              Ajuda
EOF
  exit 0
}

log_info() { echo "[$(date -Iseconds)][setup][INFO] $*"; }
log_warn() { echo "[$(date -Iseconds)][setup][WARN] $*" >&2; }
log_err()  { echo "[$(date -Iseconds)][setup][ERR] $*" >&2; }

sql_escape() {
  local val="$1"
  echo "${val//\'/\'\'}"
}

require_bin() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || { log_err "Falta dependencia: $bin"; exit 1; }
}

require_int() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" || ! "$value" =~ ^[0-9]+$ ]]; then
    log_err "$label deve ser um numero inteiro."
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --athlete-id) ATHLETE_ID="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --hr-max) HR_MAX="${2:-}"; shift 2 ;;
    --hr-rest) HR_REST="${2:-}"; shift 2 ;;
    --goal) GOAL_EVENT="${2:-}"; shift 2 ;;
    --weekly-hours) WEEKLY_HOURS="${2:-}"; shift 2 ;;
    --coach-mode) COACH_MODE="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    *) log_err "Opcao desconhecida: $1"; usage ;;
  esac
done

require_bin sqlite3

if [[ ! -f "$DB" ]]; then
  log_err "Banco nao encontrado: $DB"
  exit 1
fi

ATHLETE_ID="${ATHLETE_ID:-$ATHLETE_DEFAULT}"
HR_REST="${HR_REST:-50}"
COACH_MODE="${COACH_MODE:-moderate}"

if [[ -z "${NAME:-}" ]]; then
  read -rp "Nome do atleta: " NAME
fi
if [[ -z "${HR_MAX:-}" ]]; then
  read -rp "FC max (bpm): " HR_MAX
fi
if [[ -z "${HR_REST:-}" ]]; then
  read -rp "FC repouso (bpm) [50]: " HR_REST_INPUT
  HR_REST="${HR_REST_INPUT:-$HR_REST}"
fi
if [[ -z "${GOAL_EVENT:-}" ]]; then
  read -rp "Objetivo/evento (opcional): " GOAL_EVENT
fi
if [[ -z "${WEEKLY_HOURS:-}" ]]; then
  read -rp "Horas/semana alvo (opcional): " WEEKLY_HOURS
fi
if [[ -z "${COACH_MODE:-}" ]]; then
  read -rp "Coach mode [moderate]: " COACH_MODE_INPUT
  COACH_MODE="${COACH_MODE_INPUT:-moderate}"
fi

if [[ -z "$ATHLETE_ID" ]]; then
  log_err "athlete-id nao pode ser vazio."
  exit 1
fi

require_int "FC max" "$HR_MAX"
require_int "FC repouso" "$HR_REST"

safe_mode="$(sql_escape "$COACH_MODE")"
mode_ok="$(sqlite3 "$DB" "SELECT 1 FROM coach_policy WHERE mode='$safe_mode' LIMIT 1;")"
if [[ -z "$mode_ok" ]]; then
  log_err "coach-mode invalido: $COACH_MODE"
  exit 1
fi

safe_athlete="$(sql_escape "$ATHLETE_ID")"
exists="$(sqlite3 "$DB" "SELECT 1 FROM athlete_profile WHERE athlete_id='$safe_athlete' LIMIT 1;")"
if [[ -n "$exists" && "$FORCE" -ne 1 ]]; then
  log_err "Athlete ja existe: $ATHLETE_ID (use --force para atualizar)"
  exit 1
fi

safe_name="$(sql_escape "${NAME:-}")"
safe_goal="$(sql_escape "${GOAL_EVENT:-}")"

weekly_hours_sql="NULL"
if [[ -n "${WEEKLY_HOURS:-}" ]]; then
  weekly_hours_sql="$WEEKLY_HOURS"
fi

sql=$(cat <<SQL
BEGIN;
INSERT INTO athlete_profile (athlete_id, name, hr_max, hr_rest, goal_event, weekly_hours_target, created_at, updated_at)
VALUES ('$safe_athlete', '$safe_name', $HR_MAX, $HR_REST, '$safe_goal', $weekly_hours_sql, datetime('now'), datetime('now'))
ON CONFLICT(athlete_id) DO UPDATE SET
  name=excluded.name,
  hr_max=excluded.hr_max,
  hr_rest=excluded.hr_rest,
  goal_event=excluded.goal_event,
  weekly_hours_target=excluded.weekly_hours_target,
  updated_at=datetime('now');

INSERT INTO athlete_state (athlete_id, coach_mode, updated_at)
VALUES ('$safe_athlete', '$safe_mode', datetime('now'))
ON CONFLICT(athlete_id) DO UPDATE SET
  coach_mode=excluded.coach_mode,
  updated_at=datetime('now');
COMMIT;
SQL
)

if [[ "$DRY_RUN" -eq 1 ]]; then
  log_info "[DRY-RUN] SQL gerado:"
  echo "$sql"
  exit 0
fi

sqlite3 "$DB" "$sql"
log_info "Setup concluido para athlete_id=$ATHLETE_ID (mode=$COACH_MODE)"
