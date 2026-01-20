#!/bin/bash
#
# init_db.sh - Inicializa o banco SQLite do Ultra Coach
#
# Uso:
#   ./init_db.sh [opcoes]
#
# Opcoes:
#   --reset       Apaga e recria o banco (CUIDADO: perde todos os dados!)
#   --migrate     Aplica apenas as migrations pendentes
#   --check       Verifica se o banco esta atualizado
#   -h, --help    Mostra esta ajuda

set -euo pipefail

# ---------- Config ----------
ULTRA_COACH_PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-/opt/ultra-coach}"
ULTRA_COACH_DATA_DIR="${ULTRA_COACH_DATA_DIR:-/var/lib/ultra-coach}"
ULTRA_COACH_DB="${ULTRA_COACH_DB:-/var/lib/ultra-coach/coach.sqlite}"

SCHEMA_FILE="$ULTRA_COACH_PROJECT_DIR/sql/schema.sql"
MIGRATIONS_DIR="$ULTRA_COACH_PROJECT_DIR/sql/migrations"

# ---------- Logging ----------
log_info()  { echo "[$(date -Iseconds)][init_db][INFO] $*"; }
log_warn()  { echo "[$(date -Iseconds)][init_db][WARN] $*" >&2; }
log_err()   { echo "[$(date -Iseconds)][init_db][ERR] $*" >&2; }

# ---------- Deps ----------
command -v sqlite3 >/dev/null 2>&1 || { log_err "sqlite3 nao encontrado"; exit 1; }

# ---------- Args ----------
RESET=0
MIGRATE_ONLY=0
CHECK_ONLY=0

usage() {
  cat <<EOF
Uso: $(basename "$0") [opcoes]

Inicializa o banco SQLite do Ultra Coach.

Opcoes:
  --reset       Apaga e recria o banco (CUIDADO: perde todos os dados!)
  --migrate     Aplica apenas as migrations pendentes
  --check       Verifica se o banco esta atualizado
  -h, --help    Mostra esta ajuda

Exemplos:
  $(basename "$0")              # Inicializa banco se nao existir
  $(basename "$0") --migrate    # Aplica migrations pendentes
  $(basename "$0") --reset      # Recria banco do zero
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset)       RESET=1; shift ;;
    --migrate)     MIGRATE_ONLY=1; shift ;;
    --check)       CHECK_ONLY=1; shift ;;
    -h|--help)     usage ;;
    *)             log_err "Opcao desconhecida: $1"; usage ;;
  esac
done

# ---------- Funcoes ----------

# Cria tabela de controle de migrations se nao existir
ensure_migrations_table() {
  sqlite3 "$ULTRA_COACH_DB" <<SQL
CREATE TABLE IF NOT EXISTS _migrations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  filename TEXT NOT NULL UNIQUE,
  applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);
SQL
}

# Lista migrations ja aplicadas
get_applied_migrations() {
  sqlite3 "$ULTRA_COACH_DB" "SELECT filename FROM _migrations ORDER BY filename;" 2>/dev/null || echo ""
}

# Aplica uma migration
apply_migration() {
  local migration_file="$1"
  local filename
  filename="$(basename "$migration_file")"

  log_info "Aplicando migration: $filename"

  if sqlite3 "$ULTRA_COACH_DB" < "$migration_file"; then
    sqlite3 "$ULTRA_COACH_DB" "INSERT INTO _migrations (filename) VALUES ('$filename');"
    log_info "Migration $filename aplicada com sucesso"
    return 0
  else
    log_err "Falha ao aplicar migration $filename"
    return 1
  fi
}

# Aplica todas as migrations pendentes
apply_pending_migrations() {
  ensure_migrations_table

  local applied
  applied="$(get_applied_migrations)"

  local pending=0
  local applied_count=0

  if [[ -d "$MIGRATIONS_DIR" ]]; then
    for migration in "$MIGRATIONS_DIR"/*.sql; do
      [[ -f "$migration" ]] || continue

      local filename
      filename="$(basename "$migration")"

      if echo "$applied" | grep -qx "$filename"; then
        continue  # ja aplicada
      fi

      pending=$((pending + 1))

      if [[ $CHECK_ONLY -eq 1 ]]; then
        log_info "Pendente: $filename"
      else
        if apply_migration "$migration"; then
          applied_count=$((applied_count + 1))
        fi
      fi
    done
  fi

  if [[ $CHECK_ONLY -eq 1 ]]; then
    if [[ $pending -eq 0 ]]; then
      log_info "Banco atualizado (nenhuma migration pendente)"
    else
      log_warn "$pending migration(s) pendente(s)"
    fi
  else
    log_info "Migrations aplicadas: $applied_count"
  fi
}

# ---------- Main ----------

# Cria diretorio de dados se nao existir
if [[ ! -d "$ULTRA_COACH_DATA_DIR" ]]; then
  log_info "Criando diretorio de dados: $ULTRA_COACH_DATA_DIR"
  mkdir -p "$ULTRA_COACH_DATA_DIR"
fi

# Modo check: apenas verifica
if [[ $CHECK_ONLY -eq 1 ]]; then
  if [[ ! -f "$ULTRA_COACH_DB" ]]; then
    log_warn "Banco nao existe: $ULTRA_COACH_DB"
    exit 1
  fi
  apply_pending_migrations
  exit 0
fi

# Modo migrate: apenas migrations
if [[ $MIGRATE_ONLY -eq 1 ]]; then
  if [[ ! -f "$ULTRA_COACH_DB" ]]; then
    log_err "Banco nao existe. Execute sem --migrate primeiro."
    exit 1
  fi
  apply_pending_migrations
  exit 0
fi

# Modo reset: apaga e recria
if [[ $RESET -eq 1 ]]; then
  if [[ -f "$ULTRA_COACH_DB" ]]; then
    log_warn "Apagando banco existente: $ULTRA_COACH_DB"
    rm -f "$ULTRA_COACH_DB"
  fi
fi

# Inicializa banco se nao existir
if [[ ! -f "$ULTRA_COACH_DB" ]]; then
  log_info "Criando banco: $ULTRA_COACH_DB"

  if [[ ! -f "$SCHEMA_FILE" ]]; then
    log_err "Schema nao encontrado: $SCHEMA_FILE"
    exit 1
  fi

  if sqlite3 "$ULTRA_COACH_DB" < "$SCHEMA_FILE"; then
    log_info "Schema aplicado com sucesso"
  else
    log_err "Falha ao aplicar schema"
    exit 1
  fi
else
  log_info "Banco ja existe: $ULTRA_COACH_DB"
fi

# Aplica migrations pendentes
apply_pending_migrations

log_info "Inicializacao concluida"
