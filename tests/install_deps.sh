#!/bin/bash
set -euo pipefail

# install_deps.sh - Instala todas as dependências necessárias para testes
# Uso: ./tests/install_deps.sh [--ci]

CI_MODE=false
if [[ "${1:-}" == "--ci" ]]; then
  CI_MODE=true
fi

log() {
  echo "[$(date -Iseconds)][install_deps][INFO] $*"
}

error() {
  echo "[$(date -Iseconds)][install_deps][ERROR] $*" >&2
}

# Detectar sistema operacional
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS=$ID
else
  error "Não foi possível detectar o sistema operacional"
  exit 1
fi

log "Sistema operacional detectado: $OS"

# Instalar dependências do sistema
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
  log "Instalando dependências do sistema (apt)..."

  if [[ "$CI_MODE" == true ]]; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq sqlite3 jq curl bc netcat-openbsd shellcheck
  else
    sudo apt-get update
    sudo apt-get install -y sqlite3 jq curl bc netcat-openbsd shellcheck
  fi
else
  error "Sistema operacional não suportado: $OS"
  error "Instale manualmente: sqlite3, jq, curl, bc, netcat, shellcheck"
  exit 1
fi

# Instalar BATS
if command -v bats &>/dev/null; then
  log "BATS já instalado: $(bats --version)"
else
  log "Instalando BATS..."
  BATS_VERSION="1.11.0"
  BATS_TMP="/tmp/bats-install-$$"

  mkdir -p "$BATS_TMP"
  curl -sSL "https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz" | tar -xz -C "$BATS_TMP"

  cd "$BATS_TMP/bats-core-${BATS_VERSION}"
  sudo ./install.sh /usr/local

  rm -rf "$BATS_TMP"
  log "BATS instalado: $(bats --version)"
fi

# Instalar BATS helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_LIBS_DIR="$SCRIPT_DIR/bats-libs"

install_bats_helper() {
  local name=$1
  local repo=$2
  local target="$BATS_LIBS_DIR/$name"

  if [[ -d "$target/.git" ]]; then
    log "Atualizando $name..."
    cd "$target"
    git pull -q origin master
  else
    log "Clonando $name..."
    rm -rf "$target"
    git clone -q "$repo" "$target"
  fi
}

install_bats_helper "bats-support" "https://github.com/bats-core/bats-support.git"
install_bats_helper "bats-assert" "https://github.com/bats-core/bats-assert.git"
install_bats_helper "bats-file" "https://github.com/bats-core/bats-file.git"

# Verificar Node.js
if ! command -v node &>/dev/null; then
  error "Node.js não encontrado. Instale Node.js >= 18"
  error "Veja: https://nodejs.org/ ou use nvm"
  exit 1
fi

NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt 18 ]]; then
  error "Node.js versão $NODE_VERSION detectada. É necessário >= 18"
  exit 1
fi

log "Node.js versão válida detectada: $(node --version)"

# Instalar dependências Node.js
log "Instalando dependências Node.js..."
cd "$SCRIPT_DIR/../fit"

if [[ "$CI_MODE" == true ]]; then
  npm install --silent
else
  npm install
fi

log "Todas as dependências instaladas com sucesso!"
log ""
log "Para rodar testes:"
log "  make test          # Todos os testes"
log "  make test-unit     # Apenas unit"
log "  make test-node     # Apenas Node.js"
log "  bats tests/        # Todos os testes BATS"
