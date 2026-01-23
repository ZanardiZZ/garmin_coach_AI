#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATA_DIR="${ULTRA_COACH_DATA_DIR:-/tmp/ultra-coach-e2e}"
DB_PATH="${ULTRA_COACH_DB:-$DATA_DIR/coach.sqlite}"

export ULTRA_COACH_PROJECT_DIR="$ROOT_DIR"
export ULTRA_COACH_DATA_DIR="$DATA_DIR"
export ULTRA_COACH_DB="$DB_PATH"
export ATHLETE="zz"
export MOCK_ACTIVITY_GPS="1"
export SCREENSHOT_DIR="${SCREENSHOT_DIR:-$ROOT_DIR/tests/e2e_ui/screenshots}"

mkdir -p "$DATA_DIR"
mkdir -p "$SCREENSHOT_DIR"
rm -f "$SCREENSHOT_DIR"/*.png 2>/dev/null || true

"$ROOT_DIR/bin/init_db.sh" --reset
"$ROOT_DIR/bin/mock_seed.sh" --reset

if [[ ! -x "$ROOT_DIR/web/node_modules/.bin/playwright" ]]; then
  echo "[e2e-ui][ERR] Playwright nao instalado. Rode:"
  echo "  cd $ROOT_DIR/web && npm install"
  echo "  cd $ROOT_DIR/web && npx playwright install --with-deps chromium"
  exit 1
fi

PORT=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(('', 0))
print(s.getsockname()[1])
s.close()
PY
)

export PORT
export BASE_URL="http://localhost:${PORT}"

WEB_LOG="$DATA_DIR/web_e2e.log"
node "$ROOT_DIR/web/app.js" >"$WEB_LOG" 2>&1 &
WEB_PID=$!

cleanup() {
  kill "$WEB_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in $(seq 1 40); do
  if curl -fsS "$BASE_URL/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

cd "$ROOT_DIR/web"
BASE_URL="$BASE_URL" npx playwright test
