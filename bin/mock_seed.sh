#!/usr/bin/env bash
set -euo pipefail

: "${ULTRA_COACH_DB:=/var/lib/ultra-coach/coach.sqlite}"
: "${ATHLETE_ID:=demo}"

usage() {
  cat <<EOF
Uso: mock_seed.sh [--reset]

Cria dados mock no SQLite para testar o dashboard sem credenciais.
Também gera pontos ActivityGPS no InfluxDB local.
EOF
}

RESET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset) RESET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opcao desconhecida: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$ULTRA_COACH_DB" ]]; then
  echo "DB nao encontrado em $ULTRA_COACH_DB" >&2
  exit 1
fi

if [[ "$RESET" -eq 1 ]]; then
  sqlite3 "$ULTRA_COACH_DB" <<SQL
DELETE FROM daily_plan_ai WHERE athlete_id='$ATHLETE_ID';
DELETE FROM daily_plan WHERE athlete_id='$ATHLETE_ID';
DELETE FROM session_log WHERE athlete_id='$ATHLETE_ID';
DELETE FROM body_comp_log WHERE athlete_id='$ATHLETE_ID';
DELETE FROM weekly_state WHERE athlete_id='$ATHLETE_ID';
DELETE FROM athlete_state WHERE athlete_id='$ATHLETE_ID';
DELETE FROM athlete_profile WHERE athlete_id='$ATHLETE_ID';
SQL
fi

sqlite3 "$ULTRA_COACH_DB" <<SQL
INSERT OR REPLACE INTO athlete_profile (
  athlete_id, name, hr_max, hr_rest, weight_kg, lt_hr, lt_pace_min_km, lt_power_w,
  goal_event, weekly_hours_target, created_at, updated_at
) VALUES (
  '$ATHLETE_ID', 'Demo Athlete', 190, 50, 72.5, 170, 4.5, 320,
  'Ultra 90k', 10.0, datetime('now'), datetime('now')
);

INSERT OR REPLACE INTO athlete_state (
  athlete_id, readiness_score, fatigue_score, monotony, strain,
  weekly_load, weekly_distance_km, weekly_time_min,
  last_long_run_km, last_long_run_at, last_quality_at, coach_mode, updated_at
) VALUES (
  '$ATHLETE_ID', 72, 48, 1.1, 80,
  210, 46.2, 260,
  28.0, datetime('now','-5 days'), datetime('now','-3 days'), 'moderate', datetime('now')
);

INSERT OR REPLACE INTO weekly_state (
  athlete_id, week_start, quality_days, long_days, total_time_min, total_load, total_distance_km, updated_at
) VALUES (
  '$ATHLETE_ID', date('now','weekday 1','-7 days'), 1, 1, 260, 210, 46.2, datetime('now')
);

INSERT OR REPLACE INTO session_log (
  athlete_id, activity_id, start_at, duration_min, distance_km, avg_hr, max_hr,
  avg_pace_min_km, trimp, tags, notes, created_at
) VALUES
  ('$ATHLETE_ID', 'mock-001', datetime('now','-1 day','-2 hours'), 55, 10.5, 145, 172, 5.2, 78, 'easy,import_influx', 'Mock easy run', datetime('now')),
  ('$ATHLETE_ID', 'mock-002', datetime('now','-3 days','-2 hours'), 95, 18.3, 152, 178, 5.1, 132, 'long,import_influx', 'Mock long run', datetime('now')),
  ('$ATHLETE_ID', 'mock-003', datetime('now','-5 days','-2 hours'), 70, 12.0, 158, 182, 4.9, 110, 'quality,import_influx', 'Mock quality', datetime('now'));

INSERT OR REPLACE INTO body_comp_log (
  athlete_id, measured_at, device, bmi, body_fat_pct, body_water_pct, bone_mass_kg, muscle_mass_kg, weight_kg, created_at
) VALUES (
  '$ATHLETE_ID', datetime('now','-2 days'), 'Index S2', 22.5, 12.8, 61.5, 3.1, 35.2, 72.5, datetime('now')
);

INSERT OR REPLACE INTO daily_plan (
  athlete_id, plan_date, workout_type, prescription, readiness, fatigue, coach_mode, created_at, updated_at
) VALUES (
  '$ATHLETE_ID', date('now'), 'easy', 'auto_weekly', 72, 48, 'moderate', datetime('now'), datetime('now')
);

INSERT OR REPLACE INTO daily_plan_ai (
  athlete_id, plan_date, allowed_type, constraints_json, ai_workout_json, ai_model, status, created_at, updated_at
) VALUES (
  '$ATHLETE_ID', date('now'), 'easy',
  '{"allowed_type":"easy","duration_min":45,"duration_max":70}',
  '{"title":"Rodagem leve","duration_min":55,"segments":[{"type":"run","duration_min":55,"intensity":"z2"}]}',
  'mock', 'accepted', datetime('now'), datetime('now')
);

INSERT INTO coach_chat (athlete_id, channel, role, message, created_at)
VALUES
  ('$ATHLETE_ID', 'web', 'user', 'Treino de ontem foi puxado na subida final.', datetime('now','-2 days')),
  ('$ATHLETE_ID', 'web', 'assistant', 'Anotado. Vamos manter o proximo treino em Z2 e reduzir 10min.', datetime('now','-2 days')),
  ('$ATHLETE_ID', 'telegram', 'user', 'Hoje foi facil, ritmo conversando.', datetime('now','-1 day')),
  ('$ATHLETE_ID', 'telegram', 'assistant', 'Otimo. Podemos manter a progressao leve na semana.', datetime('now','-1 day'));

INSERT INTO athlete_feedback (athlete_id, session_date, perceived, rpe, conditions, notes, created_at)
VALUES
  ('$ATHLETE_ID', date('now','-2 days'), 'hard', 8, 'subida longa', 'Faltou perna no final', datetime('now','-2 days')),
  ('$ATHLETE_ID', date('now','-1 day'), 'easy', 4, 'tempo fresco', 'Boa recuperacao', datetime('now','-1 day'));
SQL

echo "[mock] Dados SQLite criados para athlete_id=$ATHLETE_ID em $ULTRA_COACH_DB"

INFLUX_URL="${INFLUX_URL:-http://localhost:8086/write}"
INFLUX_DB="${INFLUX_DB:-GarminStats}"

base_ts="$(date -u -d '1 day ago 06:00:00' +%s)"

points=""
for i in $(seq 0 59); do
  ts=$((base_ts + i * 60))
  lat=$(awk -v n="$i" 'BEGIN{printf "-23.550%03d", n}')
  lon=$(awk -v n="$i" 'BEGIN{printf "-46.633%03d", n}')
  hr=$((140 + (i % 20)))
  speed=$(awk -v n="$i" 'BEGIN{printf "%.2f", 3.0 + (n % 5) * 0.05}')
  dist=$(awk -v n="$i" 'BEGIN{printf "%.1f", n * 50}')
  alt=$(awk -v n="$i" 'BEGIN{printf "%.1f", 700 + (n % 10) * 1.2}')
  cad=$((160 + (i % 10)))
  stride=$(awk -v n="$i" 'BEGIN{printf "%.2f", 1.0 + (n % 5) * 0.02}')
  vratio=$(awk -v n="$i" 'BEGIN{printf "%.2f", 8.0 + (n % 5) * 0.1}')
  vosc=$(awk -v n="$i" 'BEGIN{printf "%.2f", 8.0 + (n % 5) * 0.05}')
  gct=$(awk -v n="$i" 'BEGIN{printf "%.0f", 260 + (n % 10) * 2}')
  temp=$((20 + (i % 5)))
  power=$((280 + (i % 15)))
  stamina=$((100 - i))
  ts_ns=$((ts * 1000000000))
  points+="ActivityGPS,ActivityID=mock-001,ActivityType=running Latitude=$lat,Longitude=$lon,HeartRate=$hr,Speed=$speed,Distance=$dist,Altitude=$alt,Cadence=$cad,StrideLength=$stride,VerticalRatio=$vratio,VerticalOscillation=$vosc,GroundContactTime=$gct,Temperature=$temp,Power=$power,Stamina=$stamina $ts_ns\n"
done

if command -v curl >/dev/null 2>&1; then
  curl -sS -XPOST "$INFLUX_URL?db=$INFLUX_DB" --data-binary "$points" >/dev/null 2>&1 || true
  echo "[mock] ActivityGPS escrito no InfluxDB ($INFLUX_DB)"
else
  echo "[mock][WARN] curl nao encontrado; ActivityGPS nao enviado"
fi
