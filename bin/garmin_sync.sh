#!/usr/bin/env bash
set -euo pipefail

ULTRA_COACH_PROJECT_DIR="${ULTRA_COACH_PROJECT_DIR:-/opt/ultra-coach}"

# shellcheck disable=SC1091
source /etc/ultra-coach/env 2>/dev/null || true
if command -v node >/dev/null 2>&1 && [ -f "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs" ]; then
  eval "$(node "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs")"
fi

VENV_PY="$ULTRA_COACH_PROJECT_DIR/.venv/bin/python"
if [[ -x "$VENV_PY" ]]; then
  exec "$VENV_PY" "$ULTRA_COACH_PROJECT_DIR/bin/garmin_sync.py"
fi

exec "$ULTRA_COACH_PROJECT_DIR/bin/garmin_sync.py"
