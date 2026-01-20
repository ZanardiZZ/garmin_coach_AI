#!/usr/bin/env bats

# Testes para função calc_trimp do sync_influx_to_sqlite.sh
# Fórmula TRIMP de Banister: duration * HRR * 0.64 * exp(1.92 * HRR)
# Onde HRR (Heart Rate Reserve) = (avg_hr - hr_rest) / (hr_max - hr_rest)

setup() {
  # Carrega helpers
  local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  load "$test_dir/helpers/setup_test_env"
  load "$test_dir/helpers/assert_helpers"
  load_bats_libs

  # Source da função calc_trimp
  source "$ULTRA_COACH_PROJECT_DIR/bin/sync_influx_to_sqlite.sh" 2>/dev/null || true
}

@test "valida cálculo TRIMP com valores normais" {
  # Atleta: hr_rest=48, hr_max=185 (range=137)
  # Treino 60min @ 145 bpm
  # HRR = (145-48)/(185-48) = 97/137 = 0.708
  # TRIMP = 60 * 0.708 * 0.64 * exp(1.92 * 0.708)
  #       = 60 * 0.708 * 0.64 * exp(1.359)
  #       = 60 * 0.708 * 0.64 * 3.894
  #       ≈ 105.6

  run calc_trimp 60 145 48 185

  assert_success

  # Verifica que resultado é aproximadamente 105.6 (tolerância de 5.0)
  local result="$output"
  assert_in_range "$result" 100.0 110.0 "TRIMP fora do range esperado para treino normal"
}

@test "valida cálculo TRIMP com treino leve (Z1-Z2)" {
  # Treino 45min @ 135 bpm (mais leve)
  # HRR = (135-48)/(185-48) = 87/137 = 0.635
  # Esperado: TRIMP menor que treino normal

  run calc_trimp 45 135 48 185

  assert_success

  local result="$output"
  # Deve ser < 100 (menos intenso que teste anterior)
  assert_in_range "$result" 50.0 80.0 "TRIMP incorreto para treino leve"
}

@test "valida cálculo TRIMP com treino intenso (Z3+)" {
  # Treino 75min @ 165 bpm (intenso)
  # HRR = (165-48)/(185-48) = 117/137 = 0.854
  # Esperado: TRIMP alto devido a exponencial

  run calc_trimp 75 165 48 185

  assert_success

  local result="$output"
  # Deve ser > 150 (muito intenso)
  assert_in_range "$result" 150.0 200.0 "TRIMP incorreto para treino intenso"
}

@test "valida que TRIMP é 0 quando avg_hr = hr_rest" {
  # Se HR média = HR repouso, não há esforço (HRR=0)
  run calc_trimp 60 48 48 185

  assert_success

  local result="$output"
  # TRIMP deve ser muito próximo de 0
  assert_in_range "$result" 0.0 0.1 "TRIMP deveria ser ~0 quando avg_hr=hr_rest"
}

@test "valida que TRIMP é máximo quando avg_hr = hr_max" {
  # Se HR média = HR máxima, HRR=1
  # TRIMP = 60 * 1.0 * 0.64 * exp(1.92)
  #       = 60 * 1.0 * 0.64 * 6.821
  #       ≈ 261.9

  run calc_trimp 60 185 48 185

  assert_success

  local result="$output"
  assert_in_range "$result" 250.0 270.0 "TRIMP incorreto para esforço máximo"
}

@test "valida que TRIMP retorna vazio com parâmetro nulo" {
  run calc_trimp "" 145 48 185
  assert_success
  assert_output ""

  run calc_trimp 60 "" 48 185
  assert_success
  assert_output ""

  run calc_trimp 60 145 "" 185
  assert_success
  assert_output ""

  run calc_trimp 60 145 48 ""
  assert_success
  assert_output ""
}

@test "valida que TRIMP retorna vazio quando hr_max <= hr_rest (evita div0)" {
  # hr_max = hr_rest (denominador = 0)
  run calc_trimp 60 145 48 48
  assert_success
  assert_output ""

  # hr_max < hr_rest (denominador negativo)
  run calc_trimp 60 145 50 48
  assert_success
  assert_output ""
}

@test "valida que TRIMP limita HRR entre 0 e 1" {
  # avg_hr abaixo de hr_rest (HRR seria negativo)
  # Código limita: if (hrr < 0) hrr = 0
  run calc_trimp 60 40 48 185
  assert_success

  local result="$output"
  # Deve retornar 0 ou próximo
  assert_in_range "$result" 0.0 0.1

  # avg_hr acima de hr_max (HRR seria > 1)
  # Código limita: if (hrr > 1) hrr = 1
  run calc_trimp 60 200 48 185
  assert_success

  result="$output"
  # Deve ser igual ao caso avg_hr=hr_max
  assert_in_range "$result" 250.0 270.0
}

@test "valida precisão numérica (1 casa decimal)" {
  run calc_trimp 60 145 48 185

  assert_success

  # Output deve ter formato XXX.X (1 casa decimal)
  [[ "$output" =~ ^[0-9]+\.[0-9]$ ]]
}

@test "valida proporcionalidade: dobrar duração dobra TRIMP (mesma intensidade)" {
  run calc_trimp 30 145 48 185
  local trimp_30=$output

  run calc_trimp 60 145 48 185
  local trimp_60=$output

  # trimp_60 deve ser ~2x trimp_30
  local ratio=$(echo "$trimp_60 / $trimp_30" | bc -l)
  assert_in_range "$ratio" 1.9 2.1 "TRIMP não é proporcional à duração"
}

@test "valida efeito exponencial: aumentar HR tem efeito não-linear" {
  # TRIMP @ 140 bpm
  run calc_trimp 60 140 48 185
  local trimp_140=$output

  # TRIMP @ 160 bpm
  run calc_trimp 60 160 48 185
  local trimp_160=$output

  # Razão de HR: 160/140 = 1.14 (14% maior)
  # Mas TRIMP deve ser > 1.14x devido ao exp(1.92*HRR)
  local ratio=$(echo "$trimp_160 / $trimp_140" | bc -l)

  # Ratio deve ser > 1.5 (efeito exponencial)
  assert_in_range "$ratio" 1.5 2.0 "Efeito exponencial não detectado"
}
