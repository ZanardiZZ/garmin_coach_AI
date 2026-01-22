#!/usr/bin/env bash
set -euo pipefail

: "${ULTRA_COACH_DB:=/var/lib/ultra-coach/coach.sqlite}"
: "${ATHLETE_ID:=demo}"

usage() {
  cat <<EOF
Uso: mock_seed.sh [--reset]

Cria dados mock no SQLite para testar o dashboard sem credenciais.
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
  '{\"allowed_type\":\"easy\",\"duration_min\":45,\"duration_max\":70}',
  '{\"title\":\"Rodagem leve\",\"duration_min\":55,\"segments\":[{\"type\":\"run\",\"duration_min\":55,\"intensity\":\"z2\"}]}',
  'mock', 'accepted', datetime('now'), datetime('now')
);
SQL

echo "[mock] Dados criados para athlete_id=$ATHLETE_ID em $ULTRA_COACH_DB"
