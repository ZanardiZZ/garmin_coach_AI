#!/usr/bin/env bats

# Testes para lógica de validação de workout do run_coach_daily.sh
# Valida 3 camadas quando hard_cap=0:
# 1. Scan regex em todas strings por palavras proibidas
# 2. Verificação de campo intensity nos segmentos
# 3. Detecção de padrões de repetição (10x1000, 6x5min, etc)

setup() {
  # Carrega helpers
  local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  load "$test_dir/helpers/setup_test_env"
  load "$test_dir/helpers/assert_helpers"
  load_bats_libs

  setup_test_dir
  setup_test_env_vars

  TEST_WORKOUT_JSON="$TEST_TEMP_DIR/workout.json"
  TEST_CONSTRAINTS_JSON="$TEST_TEMP_DIR/constraints.json"
}

teardown() {
  teardown_test_dir
}

# Helper: cria constraints com hard_cap especificado
create_constraints() {
  local hard_cap=$1
  local allowed_type="${2:-easy}"

  cat > "$TEST_CONSTRAINTS_JSON" <<EOF
{
  "allowed_type": "$allowed_type",
  "duration_min": 40,
  "duration_max": 80,
  "hard_minutes_cap": $hard_cap,
  "z2_hr_cap": 150,
  "z3_hr_floor": 155
}
EOF
}

# Helper: valida workout usando lógica similar ao script
validate_workout() {
  local workout_file=$1
  local constraints_file=$2

  local ALLOWED_TYPE=$(jq -r '.allowed_type' "$constraints_file")
  local DUR_MIN=$(jq -r '.duration_min' "$constraints_file")
  local DUR_MAX=$(jq -r '.duration_max' "$constraints_file")
  local HARD_CAP=$(jq -r '.hard_minutes_cap' "$constraints_file")

  # Validação básica: tipo, duração, segments
  jq -e --arg at "$ALLOWED_TYPE" --argjson dmin "$DUR_MIN" --argjson dmax "$DUR_MAX" '
    (.tipo == $at)
    and (.duracao_total_min >= $dmin and .duracao_total_min <= $dmax)
    and (.segmentos | type=="array" and length>=2)
  ' "$workout_file" >/dev/null || return 1

  if [ "$HARD_CAP" = "0" ]; then
    # 1) Proíbe Z3/Z4/tiro/threshold/VO2 explícitos
    if jq -r '.. | strings' "$workout_file" | grep -Eiq '(z3|z4|tiro|threshold|limiar|vo2|maximal|all-out)'; then
      echo "REJECT: hard_cap=0 mas detectado Z3/Z4/tiro/threshold/VO2"
      return 2
    fi

    # 2) Verifica intensities nos segmentos
    if jq -r '.segmentos[]?.intensidade // ""' "$workout_file" | grep -Eiq '(z3|z4|forte|duro|intenso|limiar|vo2)'; then
      echo "REJECT: hard_cap=0 mas segment.intensidade sugere esforço proibido"
      return 3
    fi

    # 3) Detecta padrões de repetição
    if jq -r '.. | strings' "$workout_file" | grep -Eiq '([0-9]{1,2}\s*[xX]\s*[0-9]{2,4})'; then
      echo "REJECT: hard_cap=0 mas detectado padrão de repetição"
      return 4
    fi
  fi

  return 0
}

@test "valida que workout easy válido passa validação com hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Corrida regenerativa leve",
  "descricao_curta": "60min Z1-Z2",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "warmup",
      "duracao_min": 10,
      "descricao": "Aquecimento progressivo",
      "intensidade": "Z1",
      "alvo_hr": "até 135 bpm"
    },
    {
      "ordem": 2,
      "tipo": "main",
      "duracao_min": 45,
      "descricao": "Corrida leve contínua",
      "intensidade": "Z2",
      "alvo_hr": "135-150 bpm"
    },
    {
      "ordem": 3,
      "tipo": "cooldown",
      "duracao_min": 5,
      "descricao": "Desaceleração",
      "intensidade": "Z1"
    }
  ],
  "avisos": ["Mantenha respiração confortável"],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_success
}

@test "valida que workout com Z3 explícito é rejeitado quando hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Corrida com tiros Z3",
  "descricao_curta": "60min com Z3",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Inclui trechos em Z3",
      "intensidade": "Z2-Z3"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
  assert_output --partial "Z3"
}

@test "valida que workout com intensidade Z4 no segmento é rejeitado quando hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Corrida fácil",
  "descricao_curta": "60min easy",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Corrida contínua",
      "intensidade": "Z4"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
  assert_output --partial "intensidade"
}

@test "valida que padrão de repetição 10x1000 é rejeitado quando hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Corrida com intervalos",
  "descricao_curta": "10x1000m",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "10x1000m com descanso",
      "intensidade": "Z2"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
  assert_output --partial "repetição"
}

@test "valida que padrão 6x5min é rejeitado quando hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Intervalos",
  "descricao_curta": "6x5min",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Fazer 6x5min",
      "intensidade": "Z2"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
}

@test "valida que palavra 'tiro' é rejeitada quando hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Corrida com tiros",
  "descricao_curta": "60min",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Incluir alguns tiros",
      "intensidade": "Z2"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
}

@test "valida que palavra 'limiar' é rejeitada quando hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Treino de limiar",
  "descricao_curta": "60min",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Ritmo próximo ao limiar",
      "intensidade": "Z2"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
}

@test "valida que workout com VO2 max é rejeitado quando hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Treino VO2 max",
  "descricao_curta": "60min",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Treino VO2",
      "intensidade": "Z2"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
}

@test "valida que workout com Z3 é aceito quando hard_cap>0" {
  create_constraints 30 "quality"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "quality",
  "duracao_total_min": 75,
  "objetivo": "Treino intervalado Z3",
  "descricao_curta": "75min com Z3",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "warmup",
      "duracao_min": 15,
      "descricao": "Aquecimento",
      "intensidade": "Z1-Z2"
    },
    {
      "ordem": 2,
      "tipo": "work",
      "duracao_min": 5,
      "descricao": "Tiro Z3",
      "intensidade": "Z3"
    },
    {
      "ordem": 3,
      "tipo": "cooldown",
      "duracao_min": 10,
      "descricao": "Volta à calma",
      "intensidade": "Z1"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 30, "fluids_ml_per_h": 500, "sodium_mg_per_h": 300}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_success
}

@test "valida que workout com tipo incompatível é rejeitado" {
  create_constraints 0 "easy"

  # Workout diz que é "quality" mas constraint exige "easy"
  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "quality",
  "duracao_total_min": 60,
  "objetivo": "Treino de qualidade",
  "descricao_curta": "60min quality",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Treino",
      "intensidade": "Z2"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
}

@test "valida que workout fora da faixa de duração é rejeitado" {
  create_constraints 0 "easy"

  # Constraints: 40-80min, workout: 120min
  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 120,
  "objetivo": "Corrida longa",
  "descricao_curta": "120min easy",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 120,
      "descricao": "Corrida contínua",
      "intensidade": "Z2"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
}

@test "valida que workout sem segmentos suficientes é rejeitado" {
  create_constraints 0 "easy"

  # Apenas 1 segmento (exige >= 2)
  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Corrida simples",
  "descricao_curta": "60min",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Corrida contínua",
      "intensidade": "Z2"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_failure
}

@test "valida que workout com progressivo até Z2 é aceito quando hard_cap=0" {
  create_constraints 0 "easy"

  cat > "$TEST_WORKOUT_JSON" <<'EOF'
{
  "tipo": "easy",
  "duracao_total_min": 60,
  "objetivo": "Corrida progressiva até Z2",
  "descricao_curta": "60min Z1-Z2 progressivo",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "warmup",
      "duracao_min": 10,
      "descricao": "Início Z1",
      "intensidade": "Z1"
    },
    {
      "ordem": 2,
      "tipo": "main",
      "duracao_min": 45,
      "descricao": "Progressão até Z2",
      "intensidade": "Z1-Z2",
      "alvo_hr": "até 150 bpm"
    },
    {
      "ordem": 3,
      "tipo": "cooldown",
      "duracao_min": 5,
      "descricao": "Volta à calma",
      "intensidade": "Z1"
    }
  ],
  "avisos": ["Progressão controlada"],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF

  run validate_workout "$TEST_WORKOUT_JSON" "$TEST_CONSTRAINTS_JSON"
  assert_success
}
