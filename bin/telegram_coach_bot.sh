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

reschedule_plan() {
  local from_date="$1" to_date="$2"
  local safe_athlete
  safe_athlete="$(sql_escape "$ATHLETE_ID")"
  local count_from
  count_from=$(sqlite3 "$ULTRA_COACH_DB" "SELECT COUNT(*) FROM daily_plan WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$from_date")';")
  if [[ "$count_from" -eq 0 ]]; then
    echo "Plano de origem nao encontrado."
    return 1
  fi
  local count_to
  count_to=$(sqlite3 "$ULTRA_COACH_DB" "SELECT COUNT(*) FROM daily_plan WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$to_date")';")
  if [[ "$count_to" -gt 0 ]]; then
    sqlite3 "$ULTRA_COACH_DB" <<SQL
BEGIN;
UPDATE daily_plan SET plan_date='$(sql_escape "$to_date")' WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$from_date")';
UPDATE daily_plan SET plan_date='$(sql_escape "$from_date")' WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$to_date")' AND rowid != (SELECT rowid FROM daily_plan WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$from_date")' LIMIT 1);
UPDATE daily_plan_ai SET plan_date='$(sql_escape "$to_date")' WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$from_date")';
UPDATE daily_plan_ai SET plan_date='$(sql_escape "$from_date")' WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$to_date")' AND rowid != (SELECT rowid FROM daily_plan_ai WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$from_date")' LIMIT 1);
COMMIT;
SQL
  else
    sqlite3 "$ULTRA_COACH_DB" <<SQL
BEGIN;
UPDATE daily_plan SET plan_date='$(sql_escape "$to_date")', updated_at=datetime('now') WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$from_date")';
UPDATE daily_plan_ai SET plan_date='$(sql_escape "$to_date")', updated_at=datetime('now') WHERE athlete_id='$safe_athlete' AND plan_date='$(sql_escape "$from_date")';
COMMIT;
SQL
  fi
  echo "Reagendado: ${from_date} -> ${to_date}"
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

parse_intent() {
  local text="$1"
  local tmp_body
  tmp_body="$(mktemp)"
  jq -n \
    --arg model "$MODEL" \
    --arg text "$text" \
    '{
      model:$model,
      input:[
        {role:"system",content:"Voce e um parser de intents. Responda APENAS JSON valido."},
        {role:"user",content:
          ("Interprete a mensagem e responda JSON: " +
           "{\"intent\":\"chat|feedback|reschedule|stats\",\"perceived\":\"easy|medium|hard|null\",\"rpe\":1-10|null,\"from_date\":\"YYYY-MM-DD|null\",\"to_date\":\"YYYY-MM-DD|null\",\"days\":1-365|null,\"notes\":\"string|null\"}. " +
           "Use intent=feedback quando o usuario descreve como foi o treino. " +
           "Use intent=reschedule quando pedir para mover treino. " +
           "Use intent=stats quando pedir acumulado/estatisticas (ex: ultimos 30 dias). " +
           "Use intent=chat caso contrario. " +
           "Mensagem: " + $text)
        }
      ]
    }' > "$tmp_body"
  local resp
  resp=$(curl -sS https://api.openai.com/v1/responses \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -d "@$tmp_body")
  rm -f "$tmp_body"
  echo "$resp" | jq -r '.output[0].content[0].text // empty'
}

calc_stats() {
  local days="$1"
  local safe_athlete
  safe_athlete="$(sql_escape "$ATHLETE_ID")"
  local stats
  stats=$(sqlite3 "$ULTRA_COACH_DB" <<SQL
SELECT
  ROUND(COALESCE(SUM(distance_km),0),2),
  ROUND(COALESCE(SUM(duration_min),0),1),
  ROUND(COALESCE(SUM(trimp),0),1),
  COUNT(*),
  SUM(CASE WHEN tags LIKE '%easy%' THEN 1 ELSE 0 END),
  SUM(CASE WHEN tags LIKE '%quality%' THEN 1 ELSE 0 END),
  SUM(CASE WHEN tags LIKE '%long%' THEN 1 ELSE 0 END)
FROM session_log
WHERE athlete_id='$safe_athlete'
  AND date(start_at) >= date('now','localtime','-${days} days');
SQL
)
  local total_km total_min total_trimp count easy_count quality_count long_count
  IFS='|' read -r total_km total_min total_trimp count easy_count quality_count long_count <<<"$stats"
  local pace
  if [[ "$total_km" != "0" && -n "$total_km" ]]; then
    pace=$(awk -v m="$total_min" -v km="$total_km" 'BEGIN{printf "%.2f", (m/km)}')
  else
    pace="0"
  fi

  local elev_gain="n/a"
  if [[ -n "${INFLUX_URL:-}" && -n "${INFLUX_DB:-}" ]]; then
    local act_ids
    act_ids=$(sqlite3 "$ULTRA_COACH_DB" "SELECT activity_id FROM session_log WHERE athlete_id='$(sql_escape "$ATHLETE_ID")' AND activity_id IS NOT NULL AND date(start_at) >= date('now','localtime','-${days} days');")
    if [[ -n "$act_ids" ]]; then
      local total_gain=0
      while IFS= read -r act_id; do
        [[ -z "$act_id" ]] && continue
        local payload
        payload=$(curl -sS -G "$INFLUX_URL" --data-urlencode "db=$INFLUX_DB" --data-urlencode "q=SELECT Altitude FROM ActivityGPS WHERE ActivityID='$act_id' ORDER BY time ASC")
        local gains
        gains=$(echo "$payload" | jq -r '
          (.results[0].series[0].values // []) |
          map(.[1]) as $alts |
          reduce range(1; ($alts|length)) as $i (0;
            . + ( ($alts[$i] - $alts[$i-1]) | if . > 0 then . else 0 end )
          )')
        if [[ "$gains" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
          total_gain=$(awk -v a="$total_gain" -v b="$gains" 'BEGIN{printf "%.1f", (a+b)}')
        fi
      done <<< "$act_ids"
      elev_gain="${total_gain} m"
    fi
  fi

  cat <<MSG
Resumo ${days} dias:
- Km total: ${total_km} km
- Tempo total: ${total_min} min
- Carga (TRIMP): ${total_trimp}
- Treinos: ${count} (easy ${easy_count}, quality ${quality_count}, long ${long_count})
- Pace medio: ${pace} min/km
- Elevacao acumulada: ${elev_gain}
MSG
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

      if [[ "$text" == /reschedule* ]]; then
        payload="${text#/reschedule}"
        read -r from_date to_date rest <<<"$payload"
        if [[ ! "$from_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ || ! "$to_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          send_message "$chat_id" "Uso: /reschedule YYYY-MM-DD YYYY-MM-DD"
          continue
        fi
        result=$(reschedule_plan "$from_date" "$to_date") || {
          send_message "$chat_id" "$result"
          continue
        }
        send_message "$chat_id" "$result"
        continue
      fi

      insert_chat "user" "$text"
      if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        send_message "$chat_id" "OPENAI_API_KEY nao configurada."
        continue
      fi

      intent_json="$(parse_intent "$text")"
      intent="$(echo "$intent_json" | jq -r '.intent // "chat"' 2>/dev/null || echo "chat")"
      if [[ "$intent" == "feedback" ]]; then
        perceived="$(echo "$intent_json" | jq -r '.perceived // empty' 2>/dev/null)"
        rpe="$(echo "$intent_json" | jq -r '.rpe // empty' 2>/dev/null)"
        notes="$(echo "$intent_json" | jq -r '.notes // empty' 2>/dev/null)"
        insert_feedback "$perceived" "$rpe" "$notes"
        insert_chat "assistant" "Feedback registrado."
        send_message "$chat_id" "Feedback registrado."
        continue
      fi
      if [[ "$intent" == "reschedule" ]]; then
        from_date="$(echo "$intent_json" | jq -r '.from_date // empty' 2>/dev/null)"
        to_date="$(echo "$intent_json" | jq -r '.to_date // empty' 2>/dev/null)"
        if [[ ! "$from_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ || ! "$to_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          send_message "$chat_id" "Nao entendi as datas. Ex: reagendar de 2026-01-22 para 2026-01-24."
          continue
        fi
        result=$(reschedule_plan "$from_date" "$to_date") || {
          send_message "$chat_id" "$result"
          continue
        }
        insert_chat "assistant" "$result"
        send_message "$chat_id" "$result"
        continue
      fi

      if [[ "$intent" == "stats" ]]; then
        days="$(echo "$intent_json" | jq -r '.days // 30' 2>/dev/null)"
        if ! [[ "$days" =~ ^[0-9]+$ ]]; then
          days=30
        fi
        if [[ "$days" -lt 1 ]]; then days=1; fi
        if [[ "$days" -gt 365 ]]; then days=365; fi
        reply="$(calc_stats "$days")"
        insert_chat "assistant" "$reply"
        send_message "$chat_id" "$reply"
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
