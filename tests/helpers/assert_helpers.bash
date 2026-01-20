#!/bin/bash
# assert_helpers.bash - Assertions customizadas para testes

# Assert que arquivo SQLite existe e é válido
assert_valid_sqlite_db() {
  local db_path=$1
  local msg="${2:-Database SQLite inválido: $db_path}"

  assert_file_exist "$db_path"

  # Verifica integridade
  run sqlite3 "$db_path" "PRAGMA integrity_check;"
  assert_success "$msg"
  assert_output "ok"
}

# Assert que tabela existe no database
assert_table_exists() {
  local db_path=$1
  local table_name=$2
  local msg="${3:-Tabela não existe: $table_name}"

  run sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table_name';"
  assert_success "$msg"
  assert_output "$table_name"
}

# Assert que registro existe no database
assert_record_exists() {
  local db_path=$1
  local query=$2
  local msg="${3:-Registro não encontrado}"

  run sqlite3 "$db_path" "$query"
  assert_success "$msg"
  refute_output ""
}

# Assert que contagem de registros é igual ao esperado
assert_record_count() {
  local db_path=$1
  local table=$2
  local expected_count=$3
  local where_clause="${4:-}"
  local msg="${5:-Contagem de registros incorreta em $table}"

  local query="SELECT COUNT(*) FROM $table"
  if [[ -n "$where_clause" ]]; then
    query="$query WHERE $where_clause"
  fi

  run sqlite3 "$db_path" "$query"
  assert_success
  assert_output "$expected_count" "$msg"
}

# Assert que JSON é válido
assert_valid_json() {
  local json_string=$1
  local msg="${2:-JSON inválido}"

  run jq -e . <<< "$json_string"
  assert_success "$msg"
}

# Assert que JSON contém chave
assert_json_has_key() {
  local json_string=$1
  local key=$2
  local msg="${3:-JSON não contém chave: $key}"

  run jq -e ".$key" <<< "$json_string"
  assert_success "$msg"
  refute_output "null"
}

# Assert que valor JSON é igual ao esperado
assert_json_value() {
  local json_string=$1
  local key=$2
  local expected_value=$3
  local msg="${4:-Valor JSON incorreto para $key}"

  run jq -r ".$key" <<< "$json_string"
  assert_success
  assert_output "$expected_value" "$msg"
}

# Assert que string contém substring
assert_contains() {
  local string=$1
  local substring=$2
  local msg="${3:-String não contém: $substring}"

  if [[ "$string" != *"$substring"* ]]; then
    echo "$msg" >&2
    echo "String: $string" >&2
    return 1
  fi
}

# Assert que string NÃO contém substring
assert_not_contains() {
  local string=$1
  local substring=$2
  local msg="${3:-String contém: $substring (não deveria)"

  if [[ "$string" == *"$substring"* ]]; then
    echo "$msg" >&2
    echo "String: $string" >&2
    return 1
  fi
}

# Assert que número está dentro de range
assert_in_range() {
  local value=$1
  local min=$2
  local max=$3
  local msg="${4:-Valor $value fora do range [$min, $max]}"

  if (( $(echo "$value < $min" | bc -l) )) || (( $(echo "$value > $max" | bc -l) )); then
    echo "$msg" >&2
    return 1
  fi
}

# Assert que arquivo FIT é válido (tem header correto)
assert_valid_fit_file() {
  local fit_path=$1
  local msg="${2:-Arquivo FIT inválido: $fit_path}"

  assert_file_exist "$fit_path"

  # FIT files começam com bytes específicos
  # Bytes 8-11 devem ser ".FIT"
  run dd if="$fit_path" bs=1 skip=8 count=4 2>/dev/null
  assert_success
  assert_output ".FIT" "$msg"
}

# Assert que log contém padrão
assert_log_contains() {
  local log_file=$1
  local pattern=$2
  local msg="${3:-Log não contém: $pattern}"

  assert_file_exist "$log_file"

  run grep -q "$pattern" "$log_file"
  assert_success "$msg"
}

# Assert que comando foi executado com sucesso (status 0)
assert_command_success() {
  local msg="${1:-Comando falhou}"

  assert_success "$msg"
}

# Assert que comando falhou (status não-zero)
assert_command_failure() {
  local msg="${1:-Comando deveria ter falhado}"

  assert_failure "$msg"
}

# Assert que HTTP response tem status code esperado
assert_http_status() {
  local response=$1
  local expected_status=$2
  local msg="${3:-Status HTTP incorreto}"

  local status=$(echo "$response" | head -n1 | cut -d' ' -f2)

  if [[ "$status" != "$expected_status" ]]; then
    echo "$msg" >&2
    echo "Esperado: $expected_status, Recebido: $status" >&2
    return 1
  fi
}

# Assert que valor numérico é aproximadamente igual (com tolerância)
assert_approx_equal() {
  local value=$1
  local expected=$2
  local tolerance=${3:-0.01}
  local msg="${4:-Valor não é aproximadamente igual}"

  local diff=$(echo "($value - $expected)" | bc -l | tr -d '-')

  if (( $(echo "$diff > $tolerance" | bc -l) )); then
    echo "$msg" >&2
    echo "Valor: $value, Esperado: $expected, Tolerância: $tolerance, Diff: $diff" >&2
    return 1
  fi
}
