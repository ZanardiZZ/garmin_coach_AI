#!/usr/bin/env bash
set -euo pipefail

# ---------- Config ----------
: "${ULTRA_COACH_DB:=/var/lib/ultra-coach/coach.sqlite}"
: "${ATHLETE_ID:=zz}"

INFLUX_URL="${INFLUX_URL:-http://192.168.20.115:8086/query}"
INFLUX_DB="${INFLUX_DB:-GarminStats}"

# janela de import
SYNC_DAYS="${SYNC_DAYS:-21}"
LIMIT_ROWS="${LIMIT_ROWS:-200}"

# Influx v1 auth (se existir)
INFLUX_USER="${INFLUX_USER:-}"
INFLUX_PASS="${INFLUX_PASS:-}"

MEAS="${MEAS_ACTIVITY_SUMMARY:-ActivitySummary}"
MEAS_BODY="${MEAS_BODY_COMPOSITION:-BodyComposition}"

# ---------- Deps ----------
command -v curl >/dev/null 2>&1 || { echo "[sync][ERR] curl faltando"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "[sync][ERR] jq faltando (apt-get install -y jq)"; exit 1; }
command -v sqlite3 >/dev/null 2>&1 || { echo "[sync][ERR] sqlite3 faltando"; exit 1; }

# ---------- Logging estruturado ----------
log_info()  { echo "[$(date -Iseconds)][sync][INFO] $*"; }
log_warn()  { echo "[$(date -Iseconds)][sync][WARN] $*" >&2; }
log_err()   { echo "[$(date -Iseconds)][sync][ERR] $*" >&2; }

# Alias para compatibilidade
log() { log_info "$@"; }

# Escapa aspas simples para SQL (previne SQL injection)
sql_escape() {
  local val="$1"
  # Dobra aspas simples: ' -> ''
  echo "${val//\'/\'\'}"
}

query_influx() {
  local q="$1"
  local args=( -sG "$INFLUX_URL" --data-urlencode "db=$INFLUX_DB" --data-urlencode "q=$q" )
  [[ -n "$INFLUX_USER" ]] && args+=( --data-urlencode "u=$INFLUX_USER" )
  [[ -n "$INFLUX_PASS" ]] && args+=( --data-urlencode "p=$INFLUX_PASS" )
  curl "${args[@]}"
}

# Converte timestamp UTC Z -> local "YYYY-MM-DD HH:MM:SS"
# (assumindo TZ do sistema correta - no seu caso -03 normalmente)
to_local_sql_datetime() {
  local iso="$1" # ex: 2026-01-15T09:11:00Z
  date -d "$iso" +"%F %T"
}

# TRIMP (Banister) usando HRmax e HRrest do profile
calc_trimp() {
  local dur_min="$1"
  local avg_hr="$2"
  local hr_rest="$3"
  local hr_max="$4"

  # evita div0 e null
  if [[ -z "$dur_min" || -z "$avg_hr" || -z "$hr_rest" || -z "$hr_max" ]]; then
    echo ""
    return 0
  fi

  awk -v dur="$dur_min" -v hr="$avg_hr" -v r="$hr_rest" -v m="$hr_max" '
    BEGIN{
      denom = (m - r);
      if (denom <= 0) { print ""; exit; }
      hrr = (hr - r)/denom;
      if (hrr < 0) hrr = 0;
      if (hrr > 1) hrr = 1;
      # TRIMP masculino clássico: dur * hrr * 0.64 * exp(1.92*hrr)
      trimp = dur * hrr * 0.64 * exp(1.92*hrr);
      printf "%.1f", trimp;
    }'
}

# pace min/km a partir de m/s
pace_from_mps() {
  local mps="$1"
  if [[ -z "$mps" || "$mps" == "null" ]]; then
    echo ""
    return 0
  fi
  awk -v v="$mps" 'BEGIN{
    if (v <= 0) { print ""; exit; }
    pace = (1000.0 / v) / 60.0; # min/km
    printf "%.4f", pace;
  }'
}

# ---------- Ler perfil (HRmax/HRrest) ----------
safe_athlete_id="$(sql_escape "$ATHLETE_ID")"
hr_max="$(sqlite3 "$ULTRA_COACH_DB" "SELECT hr_max FROM athlete_profile WHERE athlete_id='$safe_athlete_id' LIMIT 1;")"
hr_rest="$(sqlite3 "$ULTRA_COACH_DB" "SELECT hr_rest FROM athlete_profile WHERE athlete_id='$safe_athlete_id' LIMIT 1;")"
[[ -z "$hr_max" ]] && hr_max=""
[[ -z "$hr_rest" ]] && hr_rest=""

# ============================
# RUNNING ACTIVITIES
# ============================
Q=$(cat <<SQL
SELECT
  "activityName",
  "activityType",
  "averageHR",
  "averageSpeed",
  "distance",
  "elapsedDuration",
  "movingDuration",
  "maxHR",
  "hrTimeInZone_1",
  "hrTimeInZone_2",
  "hrTimeInZone_3",
  "hrTimeInZone_4",
  "hrTimeInZone_5"
FROM "$MEAS"
WHERE time > now() - ${SYNC_DAYS}d
  AND "activityType" = 'running'
  AND "activityName" != 'END'
  AND "averageHR" IS NOT NULL
  AND "distance" IS NOT NULL
ORDER BY time DESC
LIMIT ${LIMIT_ROWS}
SQL
)

json="$(query_influx "$Q")"

# ---------- Parse ----------
series_exists="$(echo "$json" | jq -r '.results[0].series[0]?.name // empty')"
if [[ -z "$series_exists" ]]; then
  log "Nada para importar (sem series)."
else
  # columns map
  # values: [time, activityName, activityType, averageHR, ...]
  rows="$(echo "$json" | jq -c '
    .results[0].series[0] as $s
    | ($s.columns) as $c
    | $s.values[]
    | reduce range(0; ($c|length)) as $i ({}; . + { ($c[$i]): .[$i] })
  ')"

  imported=0
  skipped=0

  while IFS= read -r row; do
    t_utc="$(echo "$row" | jq -r '.time')"
    name="$(echo "$row" | jq -r '.activityName // ""')"
    typ="$(echo "$row" | jq -r '.activityType // ""')"

    avg_hr="$(echo "$row" | jq -r '.averageHR // empty')"
    max_hr="$(echo "$row" | jq -r '.maxHR // empty')"

    dist_m="$(echo "$row" | jq -r '.distance // empty')"
    elapsed_s="$(echo "$row" | jq -r '.elapsedDuration // empty')"
    moving_s="$(echo "$row" | jq -r '.movingDuration // empty')"
    avg_mps="$(echo "$row" | jq -r '.averageSpeed // empty')"

    z1s="$(echo "$row" | jq -r '.hrTimeInZone_1 // 0')"
    z2s="$(echo "$row" | jq -r '.hrTimeInZone_2 // 0')"
    z3s="$(echo "$row" | jq -r '.hrTimeInZone_3 // 0')"
    z4s="$(echo "$row" | jq -r '.hrTimeInZone_4 // 0')"
    z5s="$(echo "$row" | jq -r '.hrTimeInZone_5 // 0')"

    # sanity
    [[ -z "$t_utc" || "$t_utc" == "null" ]] && { skipped=$((skipped+1)); continue; }
    [[ "$typ" != "running" ]] && { skipped=$((skipped+1)); continue; }
    [[ -z "$avg_hr" ]] && { skipped=$((skipped+1)); continue; }
    [[ -z "$dist_m" || "$dist_m" == "0" ]] && { skipped=$((skipped+1)); continue; }
    [[ -z "$elapsed_s" || "$elapsed_s" == "0" ]] && { skipped=$((skipped+1)); continue; }

    start_local="$(to_local_sql_datetime "$t_utc")"

    dist_km="$(awk -v m="$dist_m" 'BEGIN{printf "%.2f", (m/1000.0)}')"
    dur_min="$(awk -v s="$elapsed_s" 'BEGIN{printf "%.1f", (s/60.0)}')"
    pace_min_km="$(pace_from_mps "$avg_mps")"

    hard_min="$(awk -v a="$z3s" -v b="$z4s" -v c="$z5s" 'BEGIN{printf "%.1f", ((a+b+c)/60.0)}')"

    # tags simples e úteis
    tags="import_influx,run"
    # long por distância ou por duração
    if awk "BEGIN{exit !($dist_km>=18 || $dur_min>=110)}"; then
      tags="$tags,long"
    fi
    # quality por tempo em Z3+ (>=10 min)
    if awk "BEGIN{exit !($hard_min>=10)}"; then
      tags="$tags,quality"
    else
      tags="$tags,easy"
    fi

    trimp="$(calc_trimp "$dur_min" "$avg_hr" "$hr_rest" "$hr_max")"

    # Sanitiza strings para prevenir SQL injection
    safe_athlete="$(sql_escape "$ATHLETE_ID")"
    safe_start="$(sql_escape "$start_local")"
    safe_tags="$(sql_escape "$tags")"

    # Inserção idempotente por (athlete_id, start_at)
    sqlite3 "$ULTRA_COACH_DB" <<SQL
INSERT INTO session_log
  (athlete_id, start_at, duration_min, distance_km, avg_hr, max_hr, avg_pace_min_km, trimp, tags, created_at)
SELECT
  '$safe_athlete',
  '$safe_start',
  $dur_min,
  $dist_km,
  $avg_hr,
  ${max_hr:-NULL},
  ${pace_min_km:-NULL},
  ${trimp:-NULL},
  '$safe_tags',
  datetime('now')
WHERE NOT EXISTS (
  SELECT 1 FROM session_log
  WHERE athlete_id='$safe_athlete'
    AND start_at='$safe_start'
);
SQL

    imported=$((imported+1))
  done < <(echo "$rows")

  log "Running activities import: imported=$imported skipped=$skipped"
fi

# ============================
# BODY COMPOSITION (Index S2)
# ============================
Q_BODY=$(cat <<SQL
SELECT
  "Device",
  "SourceType",
  "bmi",
  "bodyFat",
  "bodyWater",
  "boneMass",
  "muscleMass",
  "weight"
FROM "$MEAS_BODY"
WHERE time > now() - ${SYNC_DAYS}d
  AND "SourceType" = 'INDEX_SCALE'
  AND "Device" =~ /Index/
ORDER BY time DESC
LIMIT ${LIMIT_ROWS}
SQL
)

json_body="$(query_influx "$Q_BODY")"

series_body="$(echo "$json_body" | jq -r '.results[0].series[0]?.name // empty')"
if [[ -n "$series_body" ]]; then
  rows_body="$(echo "$json_body" | jq -c '
    .results[0].series[0] as $s
    | ($s.columns) as $c
    | $s.values[]
    | reduce range(0; ($c|length)) as $i ({}; . + { ($c[$i]): .[$i] })
  ')"

  imported_body=0
  skipped_body=0

  while IFS= read -r row; do
    t_utc="$(echo "$row" | jq -r '.time')"
    dev="$(echo "$row" | jq -r '.Device // ""')"

    bmi="$(echo "$row" | jq -r '.bmi // empty')"
    fat="$(echo "$row" | jq -r '.bodyFat // empty')"
    water="$(echo "$row" | jq -r '.bodyWater // empty')"

    bone_g="$(echo "$row" | jq -r '.boneMass // empty')"
    muscle_g="$(echo "$row" | jq -r '.muscleMass // empty')"
    weight_g="$(echo "$row" | jq -r '.weight // empty')"

    [[ -z "$t_utc" || "$t_utc" == "null" ]] && { skipped_body=$((skipped_body+1)); continue; }
    start_local="$(to_local_sql_datetime "$t_utc")"

    # massas em gramas -> kg
    bone_kg=""
    muscle_kg=""
    weight_kg=""
    [[ -n "$bone_g" && "$bone_g" != "null" ]] && bone_kg="$(awk -v g="$bone_g" 'BEGIN{printf "%.3f", (g/1000.0)}')"
    [[ -n "$muscle_g" && "$muscle_g" != "null" ]] && muscle_kg="$(awk -v g="$muscle_g" 'BEGIN{printf "%.3f", (g/1000.0)}')"
    [[ -n "$weight_g" && "$weight_g" != "null" ]] && weight_kg="$(awk -v g="$weight_g" 'BEGIN{printf "%.3f", (g/1000.0)}')"

    # Sanitiza strings para prevenir SQL injection
    safe_athlete="$(sql_escape "$ATHLETE_ID")"
    safe_measured="$(sql_escape "$start_local")"

    sqlite3 "$ULTRA_COACH_DB" <<SQL
INSERT INTO body_comp_log
  (athlete_id, measured_at, device, bmi, body_fat_pct, body_water_pct, bone_mass_kg, muscle_mass_kg, weight_kg, created_at)
VALUES
  ('$safe_athlete', '$safe_measured', 'Index S2', ${bmi:-NULL}, ${fat:-NULL}, ${water:-NULL},
   ${bone_kg:-NULL}, ${muscle_kg:-NULL}, ${weight_kg:-NULL}, datetime('now'))
ON CONFLICT(athlete_id, measured_at) DO UPDATE SET
  bmi=excluded.bmi,
  body_fat_pct=excluded.body_fat_pct,
  body_water_pct=excluded.body_water_pct,
  bone_mass_kg=excluded.bone_mass_kg,
  muscle_mass_kg=excluded.muscle_mass_kg,
  weight_kg=excluded.weight_kg,
  updated_at=datetime('now');
SQL

    imported_body=$((imported_body+1))
  done < <(echo "$rows_body")

  log "BodyComposition import: imported=$imported_body skipped=$skipped_body"
else
  log "BodyComposition: nada para importar."
fi

log "Sync finalizado."
