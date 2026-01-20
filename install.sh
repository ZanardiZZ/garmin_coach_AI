#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# garmin_coach_AI installer (idempotente)
# - Centraliza paths
# - Cria symlinks
# - Prepara env
# - Instala deps do conversor FIT
# - (Opcional) Ajuda a instalar garmin-grafana
# ==========================================================

# Onde está este repo (assumindo /opt/ultra-coach)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Garmin-Grafana (opcional)
GARMINGRAFANA_DIR_DEFAULT="/opt/garmin-grafana"
GARMINGRAFANA_DIR="${GARMINGRAFANA_DIR:-$GARMINGRAFANA_DIR_DEFAULT}"
GARMINGRAFANA_REPO_DEFAULT="https://github.com/arpanghosh8453/garmin-grafana.git"
GARMINGRAFANA_REPO="${GARMINGRAFANA_REPO:-$GARMINGRAFANA_REPO_DEFAULT}"

# Opções
DO_GG=0
DO_SYMLINKS=1
DO_FIT_DEPS=1

log()  { echo "[install] $*"; }
warn() { echo "[install][WARN] $*" >&2; }
die()  { echo "[install][ERR] $*" >&2; exit 1; }

need_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Rode como root (sudo -i)."
  fi
}

usage() {
  cat <<EOF
Uso: ./install.sh [opções]

Opções:
  --with-garmin-grafana   Clona (ou atualiza) o repo garmin-grafana em $GARMINGRAFANA_DIR
  --no-symlinks           Não cria symlinks em /usr/local/bin
  --no-fit-deps           Não roda npm install em $FIT_DIR
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-garmin-grafana) DO_GG=1; shift ;;
      --no-symlinks) DO_SYMLINKS=0; shift ;;
      --no-fit-deps) DO_FIT_DEPS=0; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Opção desconhecida: $1 (use --help)" ;;
    esac
  done
}

ensure_dirs() {
  log "Criando diretórios de dados em $DATA_DIR ..."
  mkdir -p "$DATA_DIR" "$DATA_DIR/logs" "$DATA_DIR/exports"
  chmod 0755 "$DATA_DIR" || true

  log "Criando diretórios do projeto (se necessário)..."
  mkdir -p "$BIN_DIR" "$FIT_DIR" "$TEMPLATES_DIR"
}

ensure_env_file() {
  log "Preparando env central em $ENV_FILE ..."
  mkdir -p "$ENV_DIR"
  chmod 0755 "$ENV_DIR" || true

  if [[ -f "$ENV_FILE" ]]; then
    log "Env já existe (ok): $ENV_FILE"
    return 0
  fi

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
# export ULTRA_COACH_BACKUP_DIR="$DATA_DIR/backups"  # diretorio de backups

# Atleta (default: zz)
# export ATHLETE="zz"

# OpenAI
# export OPENAI_API_KEY="..."
# export MODEL="gpt-5"

# InfluxDB (fonte de dados Garmin)
# export INFLUX_URL="http://192.168.20.115:8086/query"
# export INFLUX_DB="GarminStats"

# Telegram (para enviar .fit como documento)
# export TELEGRAM_BOT_TOKEN="..."
# export TELEGRAM_CHAT_ID="..."

# Webhook n8n (notificações)
# export WEBHOOK_URL="https://n8n.zanardizz.uk/webhook/coach/inbox"
EOF

  chmod 0640 "$ENV_FILE" || true
  log "Env criado. Edite tokens em: $ENV_FILE"
}

ensure_symlinks() {
  [[ "$DO_SYMLINKS" -eq 1 ]] || { log "Pulando symlinks (--no-symlinks)."; return 0; }

  local scripts=("run_coach_daily.sh" "push_coach_message.sh" "sync_influx_to_sqlite.sh" "init_db.sh" "backup_db.sh")

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

  log "Instalando deps do conversor FIT em $FIT_DIR ..."
  cd "$FIT_DIR"
  # Se existir package-lock.json e você quiser reprodutibilidade, troque para: npm ci
  npm install --silent
  log "Deps FIT OK."
}

install_garmin_grafana() {
  [[ "$DO_GG" -eq 1 ]] || return 0

  log "Instalando/Ajudando com garmin-grafana..."
  log "Repo: $GARMINGRAFANA_REPO"
  log "Destino: $GARMINGRAFANA_DIR"

  command -v git >/dev/null 2>&1 || die "git não encontrado."

  if [[ -d "$GARMINGRAFANA_DIR/.git" ]]; then
    log "Repo já existe. Atualizando..."
    git -C "$GARMINGRAFANA_DIR" pull --ff-only || warn "Não consegui atualizar (talvez alterações locais)."
  else
    mkdir -p "$(dirname "$GARMINGRAFANA_DIR")"
    git clone "$GARMINGRAFANA_REPO" "$GARMINGRAFANA_DIR"
  fi

  cat <<'EOF'

[install] Próximos passos do garmin-grafana (não vou executar automaticamente):
- O garmin-grafana é um stack que busca dados do Garmin e popula InfluxDB, com dashboards no Grafana.
  Documentação no repo: https://github.com/arpanghosh8453/garmin-grafana :contentReference[oaicite:1]{index=1}

- Ele usa variáveis como FETCH_SELECTION para escolher quais métricas buscar. :contentReference[oaicite:2]{index=2}

Sugestão prática no seu cenário:
1) Garanta que seu InfluxDB (v1.1) esteja acessível e com bucket/org/token corretos.
2) Configure o garmin-grafana para escrever no mesmo Influx que você já usa.
3) Só depois ligue o cron do coach diário.

Se você quiser, a gente integra o coach para:
- ler direto do InfluxDB (consulta do treino do dia / métricas)
- ou ler do export gerado pelo garmin-grafana
EOF
}

init_database() {
  log "Inicializando banco de dados..."

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

  if "$init_script"; then
    log "Banco inicializado com sucesso."
  else
    warn "Falha ao inicializar banco. Verifique manualmente."
  fi
}

smoke_test() {
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
}

main() {
  parse_args "$@"
  need_root
  ensure_dirs
  ensure_env_file
  ensure_symlinks
  ensure_fit_deps
  init_database
  install_garmin_grafana
  smoke_test

  log "Instalação concluída."
}

main "$@"
