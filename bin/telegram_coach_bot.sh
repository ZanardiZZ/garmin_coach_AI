#!/usr/bin/env bash
set -euo pipefail

: "${ULTRA_COACH_DB:=/var/lib/ultra-coach/coach.sqlite}"
: "${ULTRA_COACH_PROJECT_DIR:=/opt/ultra-coach}"
: "${STATE_DIR:=/var/lib/ultra-coach}"

# shellcheck disable=SC1091
source /etc/ultra-coach/env 2>/dev/null || true
if command -v node >/dev/null 2>&1 && [ -f "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs" ]; then
  eval "$(node "$ULTRA_COACH_PROJECT_DIR/bin/config_env.mjs")"
fi

TOKEN="${TELEGRAM_BOT_TOKEN:-}"
MODEL="${MODEL:-gpt-5}"
ATHLETE_ID="${ATHLETE:-zz}"

OFFSET_FILE="$STATE_DIR/telegram.offset"
LOCK_FILE="$STATE_DIR/telegram_bot.lock"

log() { echo "[telegram_bot] $*"; }

if [[ -z "$TOKEN" ]]; then
  log "TELEGRAM_BOT_TOKEN ausente. Saindo."
  exit 0
fi

# lock simples
exec 9>"$LOCK_FILE" || exit 1
if ! flock -n 9; then
  log "Bot ja em execucao."
  exit 0
fi

sql_escape() {
  local val="$1"
  echo "${val//\'/\'\'}"
}

insert_chat() {
  local role="$1" message="$2"
  local safe_msg="$(sql_escape "$message")"
  sqlite3 "$ULTRA_COACH_DB" <<SQL
INSERT INTO coach_chat (athlete_id, channel, role, message, created_at)
VALUES ('$(sql_escape "$ATHLETE_ID")', 'telegram', '$(sql_escape "$role")', '$safe_msg', datetime('now'));
SQL
}

insert_feedback() {
  local perceived="$1" rpe="$2" notes="$3"
  local safe_notes="$(sql_escape "$notes")"
  local perceived_sql="NULL"
  local rpe_sql="NULL"
  [[ -n "$perceived" ]] && perceived_sql="'$(sql_escape "$perceived")'"
  [[ -n "$rpe" ]] && rpe_sql="$rpe"
  sqlite3 "$ULTRA_COACH_DB" <<SQL
INSERT INTO athlete_feedback (athlete_id, perceived, rpe, notes, created_at)
VALUES ('$(sql_escape "$ATHLETE_ID")', $perceived_sql, $rpe_sql, '$safe_notes', datetime('now'));
SQL
}

build_context() {
  local feedback sessions history
  feedback=$(sqlite3 "$ULTRA_COACH_DB" "SELECT COALESCE(session_date, date(created_at)) || ' ' || COALESCE(perceived,'') || ' rpe=' || COALESCE(rpe,'') || ' ' || COALESCE(conditions,'') || ' ' || COALESCE(notes,'') FROM athlete_feedback WHERE athlete_id='$(sql_escape "$ATHLETE_ID")' AND date(created_at) >= date('now','localtime','-14 days') ORDER BY created_at DESC LIMIT 10;")
  sessions=$(sqlite3 "$ULTRA_COACH_DB" "SELECT start_at || ' ' || printf('%.1fkm',distance_km) || ' ' || printf('%dmin',duration_min) || ' HR ' || avg_hr || ' ' || COALESCE(tags,'') FROM session_log WHERE athlete_id='$(sql_escape "$ATHLETE_ID")' ORDER BY start_at DESC LIMIT 5;")
  history=$(sqlite3 "$ULTRA_COACH_DB" "SELECT role || ': ' || message FROM coach_chat WHERE athlete_id='$(sql_escape "$ATHLETE_ID")' ORDER BY created_at DESC LIMIT 6;")
  echo "Feedback recente: ${feedback:-Sem feedback}"
  echo "Ultimas atividades: ${sessions:-Sem atividades}"
  echo "Historico: ${history:-Sem historico}"
}

send_message() {
  local chat_id="$1" text="$2"
  curl -sS -XPOST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${chat_id}" \
    -d "text=${text}" \
    -d "parse_mode=Markdown" \
    >/dev/null 2>&1 || true
}

call_openai() {
  local prompt="$1"
  local tmp_body
  tmp_body="$(mktemp)"
  jq -n \
    --arg model "$MODEL" \
    --arg prompt "$prompt" \
    '{model:$model,input:[{role:"system",content:"Voce e um treinador de corrida focado em ultra endurance. Responda em PT-BR, curto e pratico."},{role:"user",content:$prompt}]}' \
    > "$tmp_body"
  local resp
  resp=$(curl -sS https://api.openai.com/v1/responses \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -d "@$tmp_body")
  rm -f "$tmp_body"
  echo "$resp" | jq -r '.output[0].content[0].text // empty'
}

offset=0
if [[ -f "$OFFSET_FILE" ]]; then
  offset=$(cat "$OFFSET_FILE" | tr -d ' \t\n')
  [[ -z "$offset" ]] && offset=0
fi

log "Bot ativo."

while true; do
  updates=$(curl -sS "https://api.telegram.org/bot${TOKEN}/getUpdates?timeout=25&offset=${offset}")
  count=$(echo "$updates" | jq '.result | length')
  if [[ "$count" -gt 0 ]]; then
    for row in $(echo "$updates" | jq -c '.result[]'); do
      update_id=$(echo "$row" | jq -r '.update_id')
      chat_id=$(echo "$row" | jq -r '.message.chat.id')
      text=$(echo "$row" | jq -r '.message.text // empty')
      offset=$((update_id + 1))
      echo "$offset" > "$OFFSET_FILE"

      [[ -z "$text" ]] && continue

      if [[ "$text" == /feedback* ]]; then
        payload="${text#/feedback}"
        read -r perceived rpe rest <<<"$payload"
        notes="$rest"
        insert_feedback "$perceived" "$rpe" "$notes"
        send_message "$chat_id" "Feedback registrado."
        continue
      fi

      insert_chat "user" "$text"
      if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        send_message "$chat_id" "OPENAI_API_KEY nao configurada."
        continue
      fi
      context="$(build_context)"
      prompt="${context}\n\nMensagem: ${text}"
      reply="$(call_openai "$prompt")"
      if [[ -z "$reply" ]]; then
        reply="Sem resposta no momento."
      fi
      insert_chat "assistant" "$reply"
      send_message "$chat_id" "$reply"
    done
  fi
  sleep 2
  done
