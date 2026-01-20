# Guia de Testes - Ultra Coach

Este documento descreve a suite de testes do Ultra Coach e como usá-la.

## Visão Geral

O Ultra Coach possui uma suite abrangente de testes que cobre:
- **Testes Unitários Bash**: Funções críticas (retry_curl, calc_trimp, sql_escape, validation)
- **Testes Unitários Node.js**: Lógica de geração de FIT (validação, HR targets, conversões)
- **Testes SQL**: Integridade de schema, triggers, migrations
- **Testes de Integração**: Scripts completos (run_coach_daily, sync_influx, etc)
- **Testes E2E**: Pipeline completo do coach

## Requisitos

### Sistema
- Ubuntu/Debian Linux
- Bash 5.x
- SQLite 3.x
- Node.js >= 18
- jq, bc, curl, netcat

### Ferramentas de Teste
- BATS (Bash Automated Testing System)
- Vitest (Node.js testing framework)
- Shellcheck (linting Bash)
- ESLint (linting Node.js)

## Instalação

### Instalação Completa de Dependências
```bash
./tests/install_deps.sh
```

Este script instala:
- Dependências do sistema (apt)
- BATS e helpers
- Dependências Node.js (npm)

### Instalação de Git Hooks
```bash
./tests/install_hooks.sh
```

Instala hooks que rodam testes automaticamente:
- **pre-commit**: Testes unitários antes de cada commit
- **pre-push**: Suite completa antes de cada push

## Rodando Testes

### Comandos Rápidos (Makefile)

```bash
# Todos os testes
make test

# Apenas testes unitários
make test-unit

# Apenas testes Node.js
make test-node

# Apenas testes SQL
make test-sql

# Relatório de cobertura
make coverage

# Linting
make lint

# Limpar arquivos temporários
make clean
```

### Comandos Específicos

#### Testes Unitários Bash
```bash
# Todos
make test-unit-bash

# Arquivo específico
bats tests/unit/bash/calc_trimp.bats

# Com output detalhado
bats --print-output-on-failure tests/unit/bash/
```

#### Testes Node.js
```bash
# Todos
cd fit && npm test

# Arquivo específico
cd fit && npm test -- tests/unit/node/input_validation.test.mjs

# Watch mode
cd fit && npm run test:watch

# Com UI
cd fit && npm run test:ui
```

#### Testes SQL
```bash
make test-sql
```

#### Cobertura
```bash
# Cobertura Node.js
cd fit && npm run coverage

# Abre relatório HTML
xdg-open fit/coverage/index.html
```

## Estrutura de Diretórios

```
tests/
├── unit/               # Testes unitários
│   ├── bash/          # Funções Bash
│   │   ├── calc_trimp.bats
│   │   ├── retry_curl.bats
│   │   ├── sql_escape.bats
│   │   └── validation.bats
│   └── node/          # Funções Node.js
│       ├── input_validation.test.mjs
│       ├── hr_target_logic.test.mjs
│       └── workout_to_fit.test.mjs
├── integration/       # Testes de integração
├── e2e/              # Testes end-to-end
├── sql/              # Testes SQL
│   ├── schema_integrity.bats
│   └── triggers.bats
├── fixtures/         # Dados de teste
│   ├── databases/
│   ├── json/
│   └── openai/
├── mocks/            # Servidores mock
├── helpers/          # Utilitários de teste
│   ├── setup_test_env.bash
│   ├── assert_helpers.bash
│   └── db_helpers.bash
├── hooks/            # Git hooks
│   ├── pre-commit
│   └── pre-push
├── install_deps.sh   # Instalação de dependências
└── install_hooks.sh  # Instalação de hooks
```

## Escrevendo Testes

### Testes Bash (BATS)

```bash
#!/usr/bin/env bats

setup() {
  # Executado antes de cada teste
  local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  load "$test_dir/helpers/setup_test_env"
  load_bats_libs

  setup_test_dir
  setup_test_env_vars
}

teardown() {
  # Executado após cada teste
  teardown_test_dir
}

@test "valida que função retorna valor esperado" {
  run my_function arg1 arg2

  assert_success
  assert_output "expected output"
}
```

#### Assertions Disponíveis (bats-assert)
- `assert_success`: Verifica exit status 0
- `assert_failure`: Verifica exit status não-zero
- `assert_output`: Verifica output exato
- `assert_output --partial`: Verifica substring em output
- `assert_line`: Verifica linha específica
- `refute_output`: Verifica que output NÃO contém texto

#### Assertions Customizadas (assert_helpers.bash)
- `assert_valid_sqlite_db`: Valida integridade de DB
- `assert_table_exists`: Verifica existência de tabela
- `assert_record_exists`: Verifica existência de registro
- `assert_valid_json`: Valida JSON
- `assert_json_has_key`: Verifica chave em JSON
- `assert_contains`: Verifica substring
- `assert_in_range`: Verifica valor numérico em range
- `assert_valid_fit_file`: Valida arquivo FIT

#### Helpers de Database (db_helpers.bash)
- `db_create_full_test_db`: Cria DB completo de teste
- `db_insert_default_athlete`: Insere atleta padrão
- `db_insert_sample_sessions`: Insere sessões de exemplo
- `db_query`: Executa query e retorna resultado
- `db_get_value`: Retorna valor de célula
- `db_count`: Retorna contagem de registros
- `db_exists`: Verifica existência de registro

### Testes Node.js (Vitest)

```javascript
import { describe, it, expect } from 'vitest';
import { myFunction } from '../../../fit/my_module.mjs';

describe('myFunction - Descrição', () => {
  it('valida comportamento esperado', () => {
    const result = myFunction('input');

    expect(result).toBe('expected');
    expect(result).toContain('substring');
    expect(result).toHaveLength(10);
  });

  it('lança erro para input inválido', () => {
    expect(() => myFunction(null)).toThrow('erro esperado');
  });
});
```

#### Matchers Disponíveis (Vitest)
- `toBe()`: Igualdade estrita (===)
- `toEqual()`: Igualdade profunda (objetos/arrays)
- `toContain()`: Verifica presença em array/string
- `toThrow()`: Verifica que função lança erro
- `toBeGreaterThan()`, `toBeLessThan()`: Comparações numéricas
- `toHaveLength()`: Verifica tamanho de array/string
- `toBeInstanceOf()`: Verifica tipo

## Fixtures

### Databases
Fixtures de databases SQLite estão em `tests/fixtures/databases/`:
- Vazios (apenas schema)
- Com atleta básico
- Com histórico completo (sessões, body comp, etc)

### JSON
Fixtures JSON estão em `tests/fixtures/json/` e `tests/fixtures/openai/`:
- Respostas do InfluxDB
- Respostas da API OpenAI (válidas e inválidas)
- Constraints
- Workouts de exemplo

### Uso de Fixtures
```bash
# Em teste BATS
load_db_fixture "with_athlete"  # Carrega fixture de DB

# Em teste Node.js
import fixture from '../../../tests/fixtures/json/my_fixture.json';
```

## Estratégias de Mock

### Servidores HTTP Mock (netcat)
```bash
# Em teste BATS
start_mock_server() {
  local port=$1
  local response_file=$2

  (while true; do
    cat "$response_file" | nc -l -p "$port" -q 1 || true
  done) &

  echo $! > "$TEST_TEMP_DIR/mock_$port.pid"
}

stop_mock_server() {
  kill $(cat "$TEST_TEMP_DIR/mock_$port.pid")
}
```

### Mocking de Funções
```bash
# Em teste BATS - sobrescreve função
my_function() {
  echo "mocked output"
}

# Em teste Node.js - Vitest mocking
vi.mock('../my_module.mjs', () => ({
  myFunction: vi.fn(() => 'mocked')
}));
```

## CI/CD

### GitHub Actions
Workflow `.github/workflows/test.yml` executa automaticamente em:
- Push para `main` ou `develop`
- Pull Requests para `main` ou `develop`

Jobs executados:
- **test-bash**: Testes Bash + SQL + Shellcheck
- **test-node**: Testes Node.js (matriz: Node 18/20/22)
- **coverage**: Relatório de cobertura → Codecov
- **lint**: Linting completo

### Git Hooks
- **pre-commit**: Bloqueia commit se testes unitários falharem
- **pre-push**: Bloqueia push se qualquer teste falhar

Para bypass temporário:
```bash
git commit --no-verify
git push --no-verify
```

## Metas de Cobertura

| Componente | Meta | Atual |
|------------|------|-------|
| Funções críticas Bash | 100% | ✅ |
| Node.js (workout_to_fit) | 80% | 🚧 |
| SQL (triggers, migrations) | 100% | ✅ |
| Scripts gerais | 70% | 🚧 |

## Debugging

### Testes BATS Falhando
```bash
# Roda teste específico com output detalhado
bats --print-output-on-failure --trace tests/unit/bash/my_test.bats

# Adiciona debug no teste
@test "my test" {
  echo "Debug: valor=$valor" >&3  # >&3 vai para stderr do BATS
  run my_function
  assert_success
}
```

### Testes Node.js Falhando
```bash
# Roda com output detalhado
cd fit && npm test -- --reporter=verbose

# Debug interativo
cd fit && node --inspect-brk node_modules/.bin/vitest
```

### Testes SQL Falhando
```bash
# Inspeciona database de teste
sqlite3 /tmp/test_XXXX.sqlite
.schema
SELECT * FROM my_table;
.quit
```

## Troubleshooting

### "BATS: command not found"
```bash
./tests/install_deps.sh
```

### "Cannot find module '@garmin/fitsdk'"
```bash
cd fit && npm install
```

### "sqlite3: command not found"
```bash
sudo apt-get install sqlite3
```

### Testes Lentos
```bash
# Roda apenas testes unitários (mais rápidos)
make test-unit

# Pula testes de integração
bats tests/unit/ tests/sql/
```

### Hooks Bloqueando Commits
```bash
# Bypass temporário
git commit --no-verify

# Desabilitar permanentemente
rm .git/hooks/pre-commit .git/hooks/pre-push
```

## Contribuindo

### Antes de Submeter PR
1. ✅ Todos os testes passam: `make test`
2. ✅ Cobertura >= meta: `make coverage`
3. ✅ Linting limpo: `make lint`
4. ✅ Hooks instalados: `./tests/install_hooks.sh`

### Adicionando Novos Testes
1. Identifique componente a testar
2. Escolha tipo apropriado (unit/integration/e2e)
3. Use fixtures existentes ou crie novos
4. Siga padrões de nomenclatura:
   - Bash: `nome_funcao.bats`
   - Node: `feature.test.mjs`
5. Adicione ao Makefile se necessário
6. Documente casos de teste complexos

## Recursos

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [Vitest Documentation](https://vitest.dev/)
- [bats-assert Reference](https://github.com/bats-core/bats-assert)
- [Garmin FIT SDK](https://developer.garmin.com/fit/overview/)

## Suporte

Para problemas com testes:
1. Verifique este README
2. Veja logs detalhados: `make test-unit-bash` ou `cd fit && npm test`
3. Verifique GitHub Actions para logs de CI
4. Abra issue em: https://github.com/user/ultra-coach/issues
