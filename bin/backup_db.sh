#!/bin/bash
#
# backup_db.sh - Backup do banco SQLite do Ultra Coach
#
# Uso:
#   ./backup_db.sh [opcoes]
#
# Opcoes:
#   --compress      Comprime o backup com gzip
#   --keep N        Mantem apenas os ultimos N backups (default: 7)
#   --quiet         Nao exibe mensagens (apenas erros)
#   -h, --help      Mostra esta ajuda
#
# Pode ser usado:
#   - Manualmente antes de operacoes arriscadas
#   - Automaticamente pelo run_coach_daily.sh
#   - Via cron para backups periodicos

set -euo pipefail

# ---------- Config ----------
ULTRA_COACH_DATA_DIR="${ULTRA_COACH_DATA_DIR:-/var/lib/ultra-coach}"
ULTRA_COACH_DB="${ULTRA_COACH_DB:-/var/lib/ultra-coach/coach.sqlite}"
BACKUP_DIR="${ULTRA_COACH_BACKUP_DIR:-$ULTRA_COACH_DATA_DIR/backups}"

# ---------- Args defaults ----------
COMPRESS=0
KEEP_BACKUPS=7
QUIET=0

# ---------- Logging ----------
log_info()  { [[ $QUIET -eq 1 ]] || echo "[$(date -Iseconds)][backup][INFO] $*"; }
log_warn()  { echo "[$(date -Iseconds)][backup][WARN] $*" >&2; }
log_err()   { echo "[$(date -Iseconds)][backup][ERR] $*" >&2; }

# ---------- Args ----------
usage() {
  cat <<EOF
Uso: $(basename "$0") [opcoes]

Cria backup do banco SQLite do Ultra Coach.

Opcoes:
  --compress      Comprime o backup com gzip
  --keep N        Mantem apenas os ultimos N backups (default: 7)
  --quiet         Nao exibe mensagens (apenas erros)
  -h, --help      Mostra esta ajuda

Variaveis de ambiente:
  ULTRA_COACH_DB           Caminho do banco (default: /var/lib/ultra-coach/coach.sqlite)
  ULTRA_COACH_BACKUP_DIR   Diretorio de backups (default: /var/lib/ultra-coach/backups)

Exemplos:
  $(basename "$0")                    # Backup simples
  $(basename "$0") --compress         # Backup comprimido
  $(basename "$0") --keep 30          # Mantem 30 backups
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compress)    COMPRESS=1; shift ;;
    --keep)        KEEP_BACKUPS="$2"; shift 2 ;;
    --quiet)       QUIET=1; shift ;;
    -h|--help)     usage ;;
    *)             log_err "Opcao desconhecida: $1"; usage ;;
  esac
done

# ---------- Validacoes ----------
if [[ ! -f "$ULTRA_COACH_DB" ]]; then
  log_err "Banco nao encontrado: $ULTRA_COACH_DB"
  exit 1
fi

command -v sqlite3 >/dev/null 2>&1 || { log_err "sqlite3 nao encontrado"; exit 1; }

if [[ $COMPRESS -eq 1 ]]; then
  command -v gzip >/dev/null 2>&1 || { log_err "gzip nao encontrado"; exit 1; }
fi

# ---------- Funcoes ----------

create_backup() {
  # Cria diretorio de backup se nao existir
  mkdir -p "$BACKUP_DIR"

  # Nome do backup com timestamp
  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"
  local backup_name="coach_${timestamp}.sqlite"
  local backup_path="$BACKUP_DIR/$backup_name"

  log_info "Criando backup: $backup_path"

  # Usa sqlite3 .backup para criar copia consistente
  # (melhor que cp pois garante integridade)
  if sqlite3 "$ULTRA_COACH_DB" ".backup '$backup_path'"; then
    log_info "Backup criado com sucesso"
  else
    log_err "Falha ao criar backup"
    return 1
  fi

  # Comprime se solicitado
  if [[ $COMPRESS -eq 1 ]]; then
    log_info "Comprimindo backup..."
    if gzip "$backup_path"; then
      backup_path="${backup_path}.gz"
      log_info "Backup comprimido: $backup_path"
    else
      log_warn "Falha ao comprimir (backup nao comprimido mantido)"
    fi
  fi

  # Verifica integridade (apenas para nao comprimido)
  if [[ $COMPRESS -eq 0 ]]; then
    local integrity
    integrity=$(sqlite3 "$backup_path" "PRAGMA integrity_check;" 2>/dev/null || echo "FAIL")
    if [[ "$integrity" == "ok" ]]; then
      log_info "Integridade verificada: OK"
    else
      log_warn "Verificacao de integridade falhou: $integrity"
    fi
  fi

  # Retorna caminho do backup
  echo "$backup_path"
}

rotate_backups() {
  log_info "Rotacionando backups (mantendo ultimos $KEEP_BACKUPS)..."

  # Lista backups ordenados por data (mais antigos primeiro)
  local backups
  backups=$(find "$BACKUP_DIR" -name "coach_*.sqlite*" -type f 2>/dev/null | sort)

  local count
  count=$(echo "$backups" | grep -c . || echo 0)

  if [[ $count -le $KEEP_BACKUPS ]]; then
    log_info "Total de backups: $count (dentro do limite)"
    return 0
  fi

  # Remove os mais antigos
  local to_remove=$((count - KEEP_BACKUPS))
  log_info "Removendo $to_remove backup(s) antigo(s)..."

  echo "$backups" | head -n "$to_remove" | while read -r old_backup; do
    if [[ -n "$old_backup" && -f "$old_backup" ]]; then
      log_info "Removendo: $(basename "$old_backup")"
      rm -f "$old_backup"
    fi
  done
}

# ---------- Main ----------
backup_path=$(create_backup)
rotate_backups

log_info "Backup finalizado: $backup_path"
