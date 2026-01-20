#!/bin/bash
set -euo pipefail

# install_hooks.sh - Instala git hooks para testes automáticos

# Detecta diretório raiz do projeto
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
SOURCE_HOOKS_DIR="$PROJECT_ROOT/tests/hooks"

log() {
  echo "[$(date -Iseconds)][install_hooks][INFO] $*"
}

error() {
  echo "[$(date -Iseconds)][install_hooks][ERROR] $*" >&2
}

# Verifica se estamos em um repositório Git
if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
  error "Este não é um repositório Git. Execute este script na raiz do projeto."
  exit 1
fi

# Cria diretório de hooks se não existir
mkdir -p "$HOOKS_DIR"

# Instala pre-commit hook
if [[ -f "$SOURCE_HOOKS_DIR/pre-commit" ]]; then
  log "Instalando pre-commit hook..."
  cp "$SOURCE_HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-commit"
  chmod +x "$HOOKS_DIR/pre-commit"
  log "✅ pre-commit instalado"
else
  error "Arquivo pre-commit não encontrado em $SOURCE_HOOKS_DIR"
  exit 1
fi

# Instala pre-push hook
if [[ -f "$SOURCE_HOOKS_DIR/pre-push" ]]; then
  log "Instalando pre-push hook..."
  cp "$SOURCE_HOOKS_DIR/pre-push" "$HOOKS_DIR/pre-push"
  chmod +x "$HOOKS_DIR/pre-push"
  log "✅ pre-push instalado"
else
  error "Arquivo pre-push não encontrado em $SOURCE_HOOKS_DIR"
  exit 1
fi

log ""
log "Git hooks instalados com sucesso!"
log ""
log "Hooks ativos:"
log "  - pre-commit: Roda testes unitários antes de cada commit"
log "  - pre-push:   Roda suite completa antes de cada push"
log ""
log "Para desabilitar temporariamente, use:"
log "  git commit --no-verify"
log "  git push --no-verify"
