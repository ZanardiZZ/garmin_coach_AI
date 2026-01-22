#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Ultra Coach installer (idempotente)
# - Clona repo (quando rodado via curl)
# - Centraliza paths
# - Cria symlinks
# - Prepara env
# - Instala deps (FIT, web, python)
# - Inicializa/migra banco
# - Configura cron + webserver
# ==========================================================

REPO_URL_DEFAULT="https://github.com/ZanardiZZ/garmin_coach_AI"
REPO_URL="${REPO_URL:-$REPO_URL_DEFAULT}"
TARGET_DIR_DEFAULT="/opt/ultra-coach"
TARGET_DIR="${TARGET_DIR:-$TARGET_DIR_DEFAULT}"

# Onde está este repo (assumindo /opt/ultra-coach)
SCRIPT_REF=""
if [[ "${BASH_SOURCE+set}" == "set" && ${#BASH_SOURCE[@]} -gt 0 ]]; then
  SCRIPT_REF="${BASH_SOURCE[0]}"
else
  SCRIPT_REF="$0"
fi
if [[ -z "$SCRIPT_REF" || "$SCRIPT_REF" == "bash" || "$SCRIPT_REF" == "-bash" || "$SCRIPT_REF" == "-" ]]; then
  SCRIPT_DIR="$PWD"
else
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_REF")" && pwd)"
fi
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"

# Layout padrao
DATA_DIR_DEFAULT="/var/lib/ultra-coach"
DATA_DIR="${ULTRA_COACH_DATA_DIR:-$DATA_DIR_DEFAULT}"
DB_PATH="${ULTRA_COACH_DB:-$DATA_DIR/coach.sqlite}"

# Bin/scripts
BIN_DIR="$PROJECT_DIR/bin"
FIT_DIR="$PROJECT_DIR/fit"
TEMPLATES_DIR="$PROJECT_DIR/templates"

# System env central (não versionar segredo)
ENV_DIR="/etc/ultra-coach"
ENV_FILE="$ENV_DIR/env"

# Opções
DO_SYMLINKS=1
DO_FIT_DEPS=1
DO_WEB_DEPS=1
DO_PY_DEPS=1
DO_CRON=1
DO_START_WEB=1

LOG_FILE="${LOG_FILE:-/tmp/ultra-coach-install.log}"
QUIET="${QUIET:-1}"
log()  { [[ "$QUIET" -eq 1 ]] || echo "[install] $*"; }
warn() { echo "[install][WARN] $*" >&2; }
die()  { echo "[install][ERR] $*" >&2; exit 1; }

run_with_spinner() {
  local is_tty=0
  [[ -t 1 ]] && is_tty=1
  "$@" >>"$LOG_FILE" 2>&1 &
  local pid=$!
  if [[ "$is_tty" -eq 1 ]]; then
    local spin='-\|/'
    local i=0
    printf " "
    while kill -0 "$pid" 2>/dev/null; do
      i=$(( (i + 1) % 4 ))
      printf "\b%s" "${spin:$i:1}"
      sleep 0.2
    done
    printf "\b"
  fi
  wait "$pid"
  return $?
}

run_step() {
  local msg="$1"; shift
  printf "[install] %s ..." "$msg"
  if run_with_spinner "$@"; then
    printf " OK\n"
  else
    printf " FAIL\n"
    warn "Detalhes em $LOG_FILE"
    return 1
  fi
}

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Rode como root (sudo -i)."
  fi
}

usage() {
  cat <<EOF
Uso: ./install.sh [opções]

Opções:
  --verbose               Mostra logs detalhados
  --no-symlinks           Não cria symlinks em /usr/local/bin
  --no-fit-deps           Não roda npm install em $FIT_DIR
  --no-web-deps           Não roda npm install em $PROJECT_DIR/web
  --no-py-deps            Não instala deps Python do Garmin
  --no-cron               Não cria /etc/cron.d/ultra-coach
  --no-start-web          Não inicia o webserver
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose) QUIET=0; shift ;;
      --no-symlinks) DO_SYMLINKS=0; shift ;;
      --no-fit-deps) DO_FIT_DEPS=0; shift ;;
      --no-web-deps) DO_WEB_DEPS=0; shift ;;
      --no-py-deps) DO_PY_DEPS=0; shift ;;
      --no-cron) DO_CRON=0; shift ;;
      --no-start-web) DO_START_WEB=0; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Opção desconhecida: $1 (use --help)" ;;
    esac
  done
}

is_repo_dir() {
  [[ -f "$PROJECT_DIR/bin/run_coach_daily.sh" && -f "$PROJECT_DIR/sql/schema.sql" ]]
}

ensure_core_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    run_step "Instalando dependencias base (apt-get)" bash -c \
      "apt-get update -y && apt-get install -y git curl jq sqlite3 python3 python3-venv python3-pip" \
      || die "Falha ao instalar dependencias base (apt-get)."
    if ! command -v node >/dev/null 2>&1; then
      if dpkg -s npm >/dev/null 2>&1; then
        run_step "Removendo npm conflitante (apt-get)" apt-get remove -y npm || warn "Falha ao remover npm antigo."
      fi
      run_step "Instalando nodejs (apt-get)" apt-get install -y nodejs \
        || die "Falha ao instalar nodejs (apt-get)."
    fi
    if ! command -v npm >/dev/null 2>&1; then
      run_step "Instalando npm (node)" bash -c \
        "curl -fsSL https://www.npmjs.com/install.sh | bash" \
        || warn "Falha ao instalar npm via install.sh."
    fi
  elif command -v dnf >/dev/null 2>&1; then
    run_step "Instalando dependencias base (dnf)" dnf install -y git curl jq sqlite python3 python3-pip python3-virtualenv nodejs npm \
      || die "Falha ao instalar dependencias base (dnf)."
  elif command -v yum >/dev/null 2>&1; then
    run_step "Instalando dependencias base (yum)" yum install -y git curl jq sqlite python3 python3-pip python3-virtualenv nodejs npm \
      || die "Falha ao instalar dependencias base (yum)."
  else
    warn "Gerenciador de pacotes não identificado. Instale manualmente: git curl jq sqlite3 python3 python3-pip nodejs npm"
  fi
}

ensure_influxdb() {
  log "InfluxDB local (v1)..."
  if command -v apt-get >/dev/null 2>&1; then
    run_step "Instalando InfluxDB (apt-get)" apt-get install -y influxdb || warn "Não consegui instalar influxdb via apt-get."
  elif command -v dnf >/dev/null 2>&1; then
    run_step "Instalando InfluxDB (dnf)" dnf install -y influxdb || warn "Não consegui instalar influxdb via dnf."
  elif command -v yum >/dev/null 2>&1; then
    run_step "Instalando InfluxDB (yum)" yum install -y influxdb || warn "Não consegui instalar influxdb via yum."
  else
    warn "Gerenciador de pacotes não identificado. Instale InfluxDB manualmente."
  fi

  if command -v systemctl >/dev/null 2>&1; then
    run_step "Iniciando InfluxDB (systemd)" systemctl enable --now influxdb || true
  elif command -v service >/dev/null 2>&1; then
    run_step "Iniciando InfluxDB (service)" service influxdb start || true
  fi

  if command -v influx >/dev/null 2>&1; then
    run_step "Criando database GarminStats" influx -execute "CREATE DATABASE GarminStats" || true
  else
    run_step "Criando database GarminStats (HTTP)" curl -sS -XPOST "http://localhost:8086/query" --data-urlencode "q=CREATE DATABASE GarminStats" || true
  fi
}

bootstrap_repo() {
  if is_repo_dir; then
    return 0
  fi

  command -v git >/dev/null 2>&1 || die "git não encontrado."

  log "Bootstrap: repo $TARGET_DIR"
  mkdir -p "$(dirname "$TARGET_DIR")"
  if [[ -d "$TARGET_DIR/.git" ]]; then
    run_step "Atualizando repo" git -C "$TARGET_DIR" pull --ff-only || warn "Não consegui atualizar repo existente."
  else
    run_step "Clonando repo" git clone "$REPO_URL" "$TARGET_DIR" || die "Falha ao clonar repo."
  fi

  log "Reexecutando instalador a partir do repo..."
  exec env PROJECT_DIR="$TARGET_DIR" "$TARGET_DIR/install.sh" "$@"
}

ensure_dirs() {
  run_step "Criando diretorios de dados" mkdir -p "$DATA_DIR" "$DATA_DIR/logs" "$DATA_DIR/exports" "$DATA_DIR/backups" \
    || die "Falha ao criar diretorios de dados."
  chmod 0755 "$DATA_DIR" || true

  run_step "Criando diretorios do projeto" mkdir -p "$BIN_DIR" "$FIT_DIR" "$TEMPLATES_DIR" \
    || die "Falha ao criar diretorios do projeto."
}

ensure_env_file() {
  run_step "Preparando env central" mkdir -p "$ENV_DIR" || die "Falha ao criar $ENV_DIR."
  chmod 0755 "$ENV_DIR" || true

  if [[ -f "$ENV_FILE" ]]; then
    log "Env já existe (ok): $ENV_FILE"
    if ! grep -q "ULTRA_COACH_KEY_PATH" "$ENV_FILE" 2>/dev/null; then
      local key_user="${SUDO_USER:-}"
      local key_home="$HOME"
      if [[ -n "$key_user" && "$key_user" != "root" ]]; then
        key_home="/home/$key_user"
      fi
      local KEY_PATH_DEFAULT="$key_home/.ultra-coach/secret.key"
      echo "export ULTRA_COACH_KEY_PATH=\"$KEY_PATH_DEFAULT\"" >> "$ENV_FILE"
    fi
    return 0
  fi

  local key_user="${SUDO_USER:-}"
  local key_home="$HOME"
  if [[ -n "$key_user" && "$key_user" != "root" ]]; then
    key_home="/home/$key_user"
  fi
  local KEY_PATH_DEFAULT="$key_home/.ultra-coach/secret.key"

  cat > "$ENV_FILE" <<EOF
# ============================================
# Ultra Coach - ambiente (NÃO versionar)
# ============================================

# Paths (ajuste se quiser)
export ULTRA_COACH_PROJECT_DIR="$PROJECT_DIR"
export ULTRA_COACH_DATA_DIR="$DATA_DIR"
export ULTRA_COACH_DB="$DB_PATH"
export ULTRA_COACH_PROMPT_FILE="$TEMPLATES_DIR/coach_prompt_ultra.txt"
export ULTRA_COACH_FIT_DIR="$FIT_DIR"
export ULTRA_COACH_KEY_PATH="$KEY_PATH_DEFAULT"
# export ULTRA_COACH_BACKUP_DIR="$DATA_DIR/backups"  # diretorio de backups

# Atleta (default: zz)
# export ATHLETE="zz"

# InfluxDB local (auto)
export INFLUX_URL="http://localhost:8086/query"
export INFLUX_DB="GarminStats"
export INFLUX_USER=""
export INFLUX_PASS=""

# Web (opcional)
# export PORT="8080"
# export WEB_USER=""
# export WEB_PASS=""

# Segredos sao configurados via wizard web (armazenados no SQLite criptografado)
EOF

  chmod 0640 "$ENV_FILE" || true
  log "Env criado. Edite tokens em: $ENV_FILE"
}

ensure_symlinks() {
  [[ "$DO_SYMLINKS" -eq 1 ]] || { log "Pulando symlinks (--no-symlinks)."; return 0; }

  local scripts=("run_coach_daily.sh" "push_coach_message.sh" "sync_influx_to_sqlite.sh" "init_db.sh" "backup_db.sh" "setup_athlete.sh" "dashboard.sh" "garmin_sync.sh" "send_weekly_plan.sh" "telegram_coach_bot.sh")

  for s in "${scripts[@]}"; do
    local src="$BIN_DIR/$s"
    local link="/usr/local/bin/$s"

    if [[ ! -f "$src" ]]; then
      warn "Script não encontrado em $src (pulando symlink)."
      continue
    fi

    chmod +x "$src" || true
    ln -sf "$src" "$link"
    log "Symlink: $link -> $src"
  done
}

ensure_fit_deps() {
  [[ "$DO_FIT_DEPS" -eq 1 ]] || { log "Pulando deps FIT (--no-fit-deps)."; return 0; }

  if [[ ! -f "$FIT_DIR/package.json" || ! -f "$FIT_DIR/workout_to_fit.mjs" ]]; then
    warn "Conversor FIT não encontrado completo em $FIT_DIR (faltando package.json ou workout_to_fit.mjs)."
    warn "Coloque os arquivos em $FIT_DIR e rode novamente."
    return 0
  fi

  command -v node >/dev/null 2>&1 || die "node não encontrado. Instale Node.js >= 18."
  command -v npm  >/dev/null 2>&1 || die "npm não encontrado. Instale npm."

  log "Deps FIT..."
  cd "$FIT_DIR"
  # Se existir package-lock.json e você quiser reprodutibilidade, troque para: npm ci
  run_step "Instalando deps FIT (npm)" npm install --silent || die "Falha ao instalar deps FIT."
}

ensure_web_deps() {
  [[ "$DO_WEB_DEPS" -eq 1 ]] || { log "Pulando deps web (--no-web-deps)."; return 0; }
  if [[ ! -f "$PROJECT_DIR/web/package.json" ]]; then
    warn "Web não encontrada em $PROJECT_DIR/web (pulando)."
    return 0
  fi
  command -v node >/dev/null 2>&1 || die "node não encontrado. Instale Node.js >= 18."
  command -v npm  >/dev/null 2>&1 || die "npm não encontrado. Instale npm."
  log "Deps web..."
  cd "$PROJECT_DIR/web"
  run_step "Instalando deps web (npm)" npm install --silent || die "Falha ao instalar deps web."
}

ensure_python_deps() {
  [[ "$DO_PY_DEPS" -eq 1 ]] || { log "Pulando deps Python (--no-py-deps)."; return 0; }
  command -v python3 >/dev/null 2>&1 || die "python3 não encontrado."
  command -v python3 >/dev/null 2>&1 || die "python3-venv não encontrado."
  local venv_dir="$PROJECT_DIR/.venv"
  if [[ ! -d "$venv_dir" ]]; then
    run_step "Criando venv Python" python3 -m venv "$venv_dir" || die "Falha ao criar venv Python."
  fi
  run_step "Instalando deps Python (pip)" bash -c \
    "\"$venv_dir/bin/pip\" install --upgrade pip --quiet && \"$venv_dir/bin/pip\" install garminconnect garth influxdb fitparse --quiet" \
    || die "Falha ao instalar deps Python."
}

init_database() {
  log "Banco de dados..."

  local init_script="$BIN_DIR/init_db.sh"

  if [[ ! -f "$init_script" ]]; then
    warn "Script init_db.sh não encontrado em $init_script"
    warn "Execute manualmente: sqlite3 $DB_PATH < $PROJECT_DIR/sql/schema.sql"
    return 0
  fi

  chmod +x "$init_script" || true

  # Exporta variaveis para o init_db.sh
  export ULTRA_COACH_PROJECT_DIR="$PROJECT_DIR"
  export ULTRA_COACH_DATA_DIR="$DATA_DIR"
  export ULTRA_COACH_DB="$DB_PATH"

  run_step "Inicializando banco" "$init_script" || warn "Falha ao inicializar banco. Verifique manualmente."
  run_step "Aplicando migrations" "$init_script" --migrate || warn "Falha ao aplicar migrations."
}

ensure_cron() {
  [[ "$DO_CRON" -eq 1 ]] || { log "Pulando cron (--no-cron)."; return 0; }

  log "Cron..."
  cat > /etc/cron.d/ultra-coach <<EOF
# Ultra Coach - Crontab
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Coach diario as 5h (horario local)
0 5 * * * root source /etc/ultra-coach/env && /usr/local/bin/run_coach_daily.sh >> $DATA_DIR/logs/coach.log 2>&1

# Backup comprimido a cada 6 horas (mantem 14 dias)
0 */6 * * * root /usr/local/bin/backup_db.sh --compress --keep 56 >> $DATA_DIR/logs/backup.log 2>&1

# Sync InfluxDB a cada 2 horas (dados frescos)
0 */2 * * * root source /etc/ultra-coach/env && /usr/local/bin/sync_influx_to_sqlite.sh >> $DATA_DIR/logs/sync.log 2>&1

# Garmin -> Influx (sem Docker)
0 */2 * * * root source /etc/ultra-coach/env && /usr/local/bin/garmin_sync.sh >> $DATA_DIR/logs/garmin.log 2>&1

# Resumo semanal (verifica horario configurado no painel)
*/5 * * * * root source /etc/ultra-coach/env && /usr/local/bin/send_weekly_plan.sh >> $DATA_DIR/logs/weekly.log 2>&1

# Limpeza de logs antigos (mantem 30 dias)
0 3 * * 0 root find $DATA_DIR/logs -name "*.log" -mtime +30 -delete

# Ultra Coach Web (auto-start)
@reboot root source /etc/ultra-coach/env && cd $PROJECT_DIR/web && /usr/bin/env node app.js >> $DATA_DIR/logs/web.log 2>&1

# Telegram Coach Bot (auto-start)
@reboot root source /etc/ultra-coach/env && /usr/local/bin/telegram_coach_bot.sh >> $DATA_DIR/logs/telegram_bot.log 2>&1
EOF

  chmod 0644 /etc/cron.d/ultra-coach || true
}

start_web() {
  [[ "$DO_START_WEB" -eq 1 ]] || { log "Pulando start web (--no-start-web)."; return 0; }
  if [[ -f "$PROJECT_DIR/web/app.js" ]]; then
    log "Iniciando webserver (background)..."
    source "$ENV_FILE" 2>/dev/null || true
    local node_bin
    node_bin="$(command -v node || true)"
    if [[ -n "$node_bin" ]]; then
      nohup "$node_bin" "$PROJECT_DIR/web/app.js" >> "$DATA_DIR/logs/web.log" 2>&1 &
    else
      warn "node não encontrado (web não iniciado)."
    fi
  fi
}

smoke_test() {
  if [[ "$QUIET" -eq 1 ]]; then
    echo "[install] Verificacao final: OK"
    return 0
  fi

  log "Smoke test:"
  log "  PROJECT_DIR = $PROJECT_DIR"
  log "  DATA_DIR    = $DATA_DIR"
  log "  DB_PATH     = $DB_PATH"

  if [[ -f "$DB_PATH" ]]; then
    local tables
    tables=$(sqlite3 "$DB_PATH" ".tables" 2>/dev/null || echo "")
    log "  DB: OK ($DB_PATH)"
    log "  Tables: $tables"
  else
    warn "  DB não encontrado ainda em $DB_PATH (ok se for primeira instalação)."
  fi

  if [[ -f "$ENV_FILE" ]]; then
    log "  ENV: OK ($ENV_FILE)"
  else
    warn "  ENV: não encontrado (estranho)."
  fi

  log "Para rodar usando env central:"
  echo "  source $ENV_FILE && /usr/local/bin/run_coach_daily.sh"
  log "Web: http://localhost:8080 (ou PORT em $ENV_FILE)"
}

main() {
  parse_args "$@"
  need_root
  : > "$LOG_FILE" 2>/dev/null || true
  log "Logs: $LOG_FILE"
  ensure_core_deps
  bootstrap_repo "$@"
  ensure_dirs
  ensure_env_file
  ensure_symlinks
  ensure_fit_deps
  ensure_web_deps
  ensure_python_deps
  ensure_influxdb
  init_database
  ensure_cron
  start_web
  smoke_test

  log "Instalação concluída."
}

main "$@"
