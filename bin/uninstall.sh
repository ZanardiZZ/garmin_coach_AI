#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR_DEFAULT="/opt/ultra-coach"
DATA_DIR_DEFAULT="/var/lib/ultra-coach"
ENV_FILE_DEFAULT="/etc/ultra-coach/env"

ENV_FILE="$ENV_FILE_DEFAULT"
PROJECT_DIR="$PROJECT_DIR_DEFAULT"
DATA_DIR="$DATA_DIR_DEFAULT"

PURGE_DATA=0
REMOVE_CODE=0
REMOVE_PACKAGES=0
ASSUME_YES=0

log()  { echo "[uninstall] $*"; }
warn() { echo "[uninstall][WARN] $*" >&2; }
die()  { echo "[uninstall][ERR] $*" >&2; exit 1; }

usage() {
  cat <<EOF_USAGE
Uso: ./uninstall.sh [opcoes]

Opcoes:
  --purge-data       Remove dados em /var/lib/ultra-coach e /etc/ultra-coach
  --remove-code      Remove o codigo em /opt/ultra-coach
  --remove-packages  Remove grafana e influxdb via gerenciador de pacotes
  -y, --yes          Nao pedir confirmacao
  -h, --help         Mostra esta ajuda
EOF_USAGE
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Rode como root (sudo)."
  fi
}

confirm() {
  local msg="$1"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  read -r -p "$msg [y/N] " reply
  [[ "${reply,,}" == "y" ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge-data) PURGE_DATA=1; shift ;;
      --remove-code) REMOVE_CODE=1; shift ;;
      --remove-packages) REMOVE_PACKAGES=1; shift ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Opcao desconhecida: $1"; usage; exit 1 ;;
    esac
  done
}

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi

  PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-$PROJECT_DIR}"
  DATA_DIR="${ULTRA_COACH_DATA_DIR:-$DATA_DIR}"
}

stop_web() {
  log "Parando webserver..."
  pkill -f "node.*${PROJECT_DIR}/web/app.js" >/dev/null 2>&1 || true
}

stop_services() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now grafana-server >/dev/null 2>&1 || true
    systemctl disable --now influxdb >/dev/null 2>&1 || true
  elif command -v service >/dev/null 2>&1; then
    service grafana-server stop >/dev/null 2>&1 || true
    service influxdb stop >/dev/null 2>&1 || true
  fi
}

remove_cron() {
  log "Removendo cron..."
  rm -f /etc/cron.d/ultra-coach
}

remove_symlinks() {
  log "Removendo symlinks..."
  local scripts=("run_coach_daily.sh" "push_coach_message.sh" "sync_influx_to_sqlite.sh" "init_db.sh" "backup_db.sh" "setup_athlete.sh" "dashboard.sh" "garmin_sync.sh" "send_weekly_plan.sh" "telegram_coach_bot.sh" "uninstall.sh")
  local s
  for s in "${scripts[@]}"; do
    rm -f "/usr/local/bin/$s"
  done
}

remove_grafana_provisioning() {
  rm -f /etc/grafana/provisioning/datasources/ultra-coach.yml
  rm -f /etc/grafana/provisioning/dashboards/ultra-coach.yml
}

remove_packages() {
  [[ "$REMOVE_PACKAGES" -eq 1 ]] || return 0
  if ! confirm "Remover pacotes grafana e influxdb?"; then
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    apt-get remove -y grafana influxdb || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf remove -y grafana influxdb || true
  elif command -v yum >/dev/null 2>&1; then
    yum remove -y grafana influxdb || true
  else
    warn "Gerenciador de pacotes nao identificado. Remova manualmente."
  fi
}

remove_data() {
  [[ "$PURGE_DATA" -eq 1 ]] || return 0
  if ! confirm "Remover dados em $DATA_DIR e /etc/ultra-coach?"; then
    return 0
  fi
  if [[ -n "${ULTRA_COACH_KEY_PATH:-}" ]]; then
    rm -f "$ULTRA_COACH_KEY_PATH" || true
  fi
  rm -rf "$DATA_DIR" /etc/ultra-coach
}

remove_code() {
  [[ "$REMOVE_CODE" -eq 1 ]] || return 0
  if ! confirm "Remover codigo em $PROJECT_DIR?"; then
    return 0
  fi
  rm -rf "$PROJECT_DIR"
}

main() {
  parse_args "$@"
  need_root
  load_env
  stop_web
  stop_services
  remove_cron
  remove_symlinks
  remove_grafana_provisioning
  remove_packages
  remove_data
  remove_code
  log "Uninstall concluido."
}

main "$@"
