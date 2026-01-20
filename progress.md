# Ultra Coach - Histórico de Progresso

**Projeto:** Sistema de treinos de corrida com IA focado em ultra-endurance (12h / ~90km)
**Última atualização:** 2026-01-17
**Status:** ✅ Refatoração completa finalizada

---

## 📋 Sumário

- [Visão Geral do Projeto](#visão-geral-do-projeto)
- [Arquitetura](#arquitetura)
- [Mudanças Implementadas](#mudanças-implementadas)
- [Arquivos Criados/Modificados](#arquivos-criadosmodificados)
- [Próximos Passos](#próximos-passos)

---

## Visão Geral do Projeto

**Ultra Coach** é um sistema automatizado que:

1. **Sincroniza** dados do Garmin (atividades + composição corporal) via InfluxDB
2. **Analisa** estado do atleta (fadiga, prontidão, monotonia, carga)
3. **Planeja** treinos semanais seguindo políticas de treinamento
4. **Gera** treinos detalhados usando IA (OpenAI GPT-5) com constraints específicas
5. **Valida** se o treino gerado respeita as regras de segurança
6. **Converte** para formato FIT (compatível com Garmin)
7. **Notifica** atleta via Telegram com treino do dia

### Tecnologias

- **Backend:** Bash scripts + SQLite + Node.js
- **IA:** OpenAI API (GPT-5)
- **Dados:** InfluxDB v1.1 (Garmin), SQLite (coach)
- **Notificações:** Telegram + n8n webhooks
- **FIT:** @garmin/fitsdk (Node.js)

---

## Arquitetura

```
┌─────────────────┐
│  Garmin Watch   │
└────────┬────────┘
         │ (sync via garmin-grafana)
         ▼
┌─────────────────┐
│   InfluxDB v1   │
│  (ActivitySummary,
│   BodyComposition)
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│  sync_influx_to_sqlite.sh                       │
│  ↓                                               │
│  SQLite: session_log, body_comp_log             │
└────────┬────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│  run_coach_daily.sh (orquestrador principal)    │
│                                                  │
│  1. Backup automático                           │
│  2. Calcula athlete_state (readiness/fatigue)   │
│  3. Decide workout_type (easy/quality/long)     │
│  4. Gera constraints JSON                       │
│  5. Chama OpenAI com prompt especializado       │
│  6. Valida resposta da IA                       │
│  7. Salva no SQLite                             │
│  8. Converte para FIT (workout_to_fit.mjs)      │
│  9. Envia Telegram                              │
└────────┬────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐       ┌──────────────────┐
│ push_coach_     │──────▶│  n8n webhook     │
│ message.sh      │       │  ↓               │
└─────────────────┘       │  Telegram Bot    │
                          └──────────────────┘
```

---

## Mudanças Implementadas

### 🐛 **Correção de Bugs Críticos**

#### 1. ✅ Ordem de funções em `sync_influx_to_sqlite.sh`
**Problema:** Função `query_influx()` era chamada antes de ser definida.
**Solução:** Reorganizamos o arquivo na ordem correta:
- Deps check → Helpers → Profile read → Running activities → Body composition

**Arquivos:** `bin/sync_influx_to_sqlite.sh:42-48`

---

#### 2. ✅ Expansão de variável em `push_coach_message.sh`
**Problema:** `$PLAN_DATE` não expandia dentro de heredoc com aspas simples.
**Solução:** Substituímos heredoc por string quotada com escape correto.

**Antes:**
```bash
SQL=$(cat <<'EOF'
  ... WHERE plan_date = '$PLAN_DATE' ...
EOF
)
```

**Depois:**
```bash
SQL="
  ... WHERE plan_date = '$PLAN_DATE' ...
"
```

**Arquivos:** `bin/push_coach_message.sh:23-83`

---

### 🔒 **Segurança e Robustez**

#### 3. ✅ Sanitização SQL (prevenção de SQL injection)
**Problema:** Valores de usuário inseridos diretamente em queries SQL.
**Solução:** Função `sql_escape()` que dobra aspas simples (`'` → `''`).

```bash
sql_escape() {
  local val="$1"
  echo "${val//\'/\'\'}"
}

safe_athlete="$(sql_escape "$ATHLETE_ID")"
sqlite3 "$DB" "INSERT INTO ... VALUES ('$safe_athlete', ...)"
```

**Arquivos:** `bin/sync_influx_to_sqlite.sh:35-40,98,202-204,294-295`

---

#### 4. ✅ Verificação de código HTTP na chamada OpenAI
**Problema:** Script não verificava se OpenAI retornou erro (5xx, 4xx).
**Solução:** Verificação explícita do HTTP code + registro de rejeição.

```bash
HTTP_CODE=$(retry_curl 3 "$TMP_COACH_RESP" ...)

if [ "$HTTP_CODE" != "200" ]; then
  ERROR_MSG=$(jq -r '.error.message // "Erro desconhecido"' "$TMP_COACH_RESP")
  reject_plan "OpenAI retornou HTTP $HTTP_CODE: $ERROR_MSG"
  exit 2
fi
```

**Arquivos:** `bin/run_coach_daily.sh:414-425`

---

#### 5. ✅ Arquivos temporários seguros (mktemp)
**Problema:** Uso de paths `/tmp` fixos previsíveis (vulnerável a race conditions).
**Solução:** `mktemp -d` com cleanup automático via trap.

```bash
TMPDIR=$(mktemp -d -t ultra-coach.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

TMP_COACH_BODY="$TMPDIR/coach_body.json"
TMP_WORKOUT="$TMPDIR/workout.json"
# ...
```

**Arquivos:** `bin/run_coach_daily.sh:106-115`

---

### 🛠️ **Manutenibilidade**

#### 6. ✅ Variável `$ATHLETE` em vez de hardcode 'zz'
**Problema:** Athlete ID 'zz' estava hardcoded em todos os scripts.
**Solução:** Variável de ambiente `ATHLETE` com fallback para 'zz'.

```bash
ATHLETE="${ATHLETE:-zz}"
```

**Arquivos:** `bin/run_coach_daily.sh:85`, `bin/sync_influx_to_sqlite.sh:6`, `bin/push_coach_message.sh:18`

---

#### 7. ✅ Configurações via variáveis de ambiente
**Problema:** URLs, tokens e modelos estavam hardcoded nos scripts.
**Solução:** Variáveis de ambiente centralizadas em `/etc/ultra-coach/env`.

**Variáveis adicionadas:**
- `MODEL` (default: gpt-5)
- `INFLUX_URL`, `INFLUX_DB`, `INFLUX_USER`, `INFLUX_PASS`
- `WEBHOOK_URL`
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`

**Arquivos:** `install.sh:94-123`, `bin/run_coach_daily.sh:86-89`

---

#### 8. ✅ Logging estruturado em todos os scripts
**Problema:** Logs inconsistentes (echo simples, sem timestamp).
**Solução:** Funções padronizadas `log_info()`, `log_warn()`, `log_err()`.

```bash
log_info()  { echo "[$(date -Iseconds)][INFO] $*"; }
log_warn()  { echo "[$(date -Iseconds)][WARN] $*" >&2; }
log_err()   { echo "[$(date -Iseconds)][ERR] $*" >&2; }
```

**Formato:** `[2026-01-17T08:30:15-03:00][sync][INFO] Running activities import: imported=15 skipped=2`

**Arquivos:** Todos os scripts em `bin/`

---

### 📊 **Rastreabilidade**

#### 9. ✅ Coluna `rejection_reason` e função `reject_plan()`
**Problema:** Quando treino era rejeitado, não havia registro do motivo.
**Solução:**
- Migration SQL adicionando coluna `rejection_reason`
- Função `reject_plan()` que registra motivo no banco

```bash
reject_plan() {
  local reason="$1"
  local safe_reason="${reason//\'/\'\'}"
  sqlite3 "$DB" "UPDATE daily_plan_ai
    SET status='rejected',
        rejection_reason='$safe_reason',
        updated_at=datetime('now')
    WHERE athlete_id='$ATHLETE' AND plan_date='$PLAN_DATE';"
  log_err "$reason"
}
```

**Arquivos:** `sql/migrations/001_add_rejection_reason.sql`, `bin/run_coach_daily.sh:43-48`

---

### 🌐 **Confiabilidade de Rede**

#### 10. ✅ Retry com exponential backoff
**Problema:** Chamadas de rede falhavam permanentemente em erros temporários.
**Solução:** Função `retry_curl()` com 3 tentativas e backoff exponencial (2s, 4s, 8s).

```bash
retry_curl() {
  local max_attempts="$1"
  local output_file="$2"
  shift 2

  local attempt=1
  local wait_time=2

  while [ $attempt -le $max_attempts ]; do
    http_code=$(curl -sS -w "%{http_code}" -o "$output_file" "$@")

    # Sucesso ou erro de cliente (4xx) - não faz retry
    if [[ "$http_code" =~ ^2 ]] || [[ "$http_code" =~ ^4 ]]; then
      echo "$http_code"
      return 0
    fi

    # Erro de servidor (5xx) - faz retry
    if [ $attempt -lt $max_attempts ]; then
      log_warn "Tentativa $attempt/$max_attempts falhou (HTTP $http_code). Aguardando ${wait_time}s..."
      sleep $wait_time
      wait_time=$((wait_time * 2))  # exponential backoff
    fi

    attempt=$((attempt + 1))
  done

  echo "$http_code"
  return 1
}
```

**Arquivos:** `bin/run_coach_daily.sh:52-82`

---

### 🧪 **Debugging e Testing**

#### 11. ✅ Modo `--dry-run` e `--verbose`
**Problema:** Difícil testar sem chamar OpenAI ou modificar banco.
**Solução:** Argumentos de linha de comando para simulação.

```bash
# Uso:
./run_coach_daily.sh --dry-run --verbose

# Comportamento:
# - Não chama OpenAI
# - Não modifica banco
# - Mostra constraints e payload que seria enviado
# - Não faz backup
```

**Arquivos:** `bin/run_coach_daily.sh:12-35,92-97,404-411`

---

### ✅ **Validação de Dados**

#### 12. ✅ Validação robusta em `workout_to_fit.mjs`
**Problema:** Conversor aceitava JSON inválido e falhava silenciosamente.
**Solução:** Reescrita completa com validação detalhada.

**Melhorias:**
- Função `validateWorkout()` com mensagens de erro claras
- Função `readJsonFile()` com tratamento de erros
- Help (`--help`) completo
- Logging estruturado
- Exit codes específicos

```javascript
function validateWorkout(workout) {
  const errors = [];

  if (!workout || typeof workout !== 'object') {
    errors.push('Workout deve ser um objeto JSON válido');
    return errors;
  }

  if (!workout.segments) {
    errors.push('Campo "segments" é obrigatório');
  } else if (!Array.isArray(workout.segments)) {
    errors.push('Campo "segments" deve ser um array');
  } else if (workout.segments.length === 0) {
    errors.push('Array "segments" não pode estar vazio');
  } else {
    workout.segments.forEach((seg, i) => {
      if (!seg.name) {
        errors.push(`Segment[${i}]: campo "name" é obrigatório`);
      }
      if (typeof seg.duration_min !== 'number' || seg.duration_min <= 0) {
        errors.push(`Segment[${i}]: "duration_min" deve ser número positivo`);
      }
    });
  }

  return errors;
}
```

**Arquivos:** `fit/workout_to_fit.mjs` (reescrita completa)

---

### 🤖 **Qualidade da IA**

#### 13. ✅ Prompt melhorado com JSON schema e few-shot examples
**Problema:** IA às vezes gerava treinos fora do padrão esperado.
**Solução:** Prompt reestruturado com:

1. **JSON Schema explícito** com descrições de cada campo
2. **Exemplos few-shot** (2 exemplos completos):
   - Exemplo 1: Treino EASY (hard_cap=0)
   - Exemplo 2: Treino LONG (main, sábado, 180 min)
3. **Regras absolutas** claramente numeradas
4. **Regras específicas para long runs** (main vs secondary)

**Estrutura do prompt:**
```
1. Definição do papel
2. JSON Schema obrigatório
3. Regras absolutas (1-6)
4. Regras para long runs
5. Exemplo 1 (EASY)
6. Exemplo 2 (LONG)
```

**Arquivos:** `templates/coach_prompt_ultra.txt:1-134`

---

### 🗄️ **Infraestrutura de Dados**

#### 14. ✅ Schema SQL centralizado
**Problema:** Definições de tabela embutidas nos scripts, difícil de versionar.
**Solução:** Schema unificado em `sql/schema.sql` + sistema de migrations.

**Arquivos criados:**
- `sql/schema.sql` - Schema completo com:
  - 8 tabelas principais
  - Índices otimizados
  - Trigger automático para `weekly_state`
  - 2 views úteis (`v_athlete_summary`, `v_today_plan`)
  - Políticas padrão de coach

- `bin/init_db.sh` - Gerenciador de banco:
  - `--reset` - Recria banco (⚠️ perde dados)
  - `--migrate` - Aplica migrations pendentes
  - `--check` - Verifica status
  - Sistema de controle via tabela `_migrations`

**Exemplo de uso:**
```bash
# Primeira instalação
init_db.sh

# Aplicar novas migrations
init_db.sh --migrate

# Verificar status
init_db.sh --check

# Recriar do zero (cuidado!)
init_db.sh --reset
```

**Arquivos:** `sql/schema.sql`, `bin/init_db.sh`

---

### 💾 **Backup e Disaster Recovery**

#### 15. ✅ Backup automático do SQLite
**Problema:** Nenhum backup antes de operações críticas (atualização do estado).
**Solução:** Sistema completo de backup com rotação automática.

**Arquivo criado:** `bin/backup_db.sh`

**Features:**
- `--compress` - Compressão gzip
- `--keep N` - Mantém últimos N backups (default: 7)
- `--quiet` - Execução silenciosa
- Usa `sqlite3 .backup` (garante consistência)
- Verificação de integridade (`PRAGMA integrity_check`)
- Rotação automática de backups antigos

**Integração:**
- Backup automático no início de `run_coach_daily.sh`
- Respeitando `--dry-run` (não faz backup em modo simulação)
- Tolerante a falhas (avisa mas continua)

**Exemplo de uso:**
```bash
# Backup manual
backup_db.sh

# Backup comprimido
backup_db.sh --compress

# Manter apenas últimos 30 dias
backup_db.sh --compress --keep 30

# Backup silencioso (via cron)
backup_db.sh --quiet --compress --keep 14
```

**Estrutura de backups:**
```
/var/lib/ultra-coach/backups/
├── coach_20260115_053000.sqlite
├── coach_20260116_053000.sqlite.gz
├── coach_20260117_053000.sqlite.gz
└── ...
```

**Arquivos:** `bin/backup_db.sh`, `bin/run_coach_daily.sh:50-64,133-136`

---

## Arquivos Criados/Modificados

### ✨ Novos Arquivos

| Arquivo | Descrição | Linhas |
|---------|-----------|--------|
| `sql/schema.sql` | Schema SQL centralizado completo | 248 |
| `sql/migrations/001_add_rejection_reason.sql` | Migration: coluna rejection_reason | 6 |
| `bin/init_db.sh` | Gerenciador de banco e migrations | 227 |
| `bin/backup_db.sh` | Sistema de backup com rotação | 161 |
| `progress.md` | Este documento | - |

### 🔧 Arquivos Modificados

| Arquivo | Mudanças Principais |
|---------|---------------------|
| `bin/run_coach_daily.sh` | Backup automático, retry, dry-run, logging, reject_plan(), mktemp, HTTP check |
| `bin/sync_influx_to_sqlite.sh` | Ordem de funções, sql_escape(), logging estruturado |
| `bin/push_coach_message.sh` | Correção expansão $PLAN_DATE, logging |
| `fit/workout_to_fit.mjs` | Reescrita completa com validação robusta |
| `templates/coach_prompt_ultra.txt` | JSON schema + exemplos few-shot |
| `install.sh` | Integração init_db.sh, backup_db.sh, symlinks adicionais |

### 📊 Estatísticas

- **Arquivos criados:** 5
- **Arquivos modificados:** 6
- **Linhas adicionadas:** ~1.200
- **Bugs críticos corrigidos:** 2
- **Melhorias de segurança:** 3
- **Melhorias de manutenibilidade:** 3
- **Features novas:** 7

---

## Próximos Passos

### 🚀 Prioridade Alta (Fazer primeiro)

#### 1. Testes e Validação End-to-End
**Objetivo:** Garantir que todo o pipeline funciona corretamente.

**Checklist:**
- [ ] Testar sync InfluxDB → SQLite com dados reais
- [ ] Validar cálculo de `athlete_state` (readiness/fatigue)
- [ ] Testar geração de treino para cada tipo (easy/quality/long/recovery)
- [ ] Verificar se IA respeita `hard_minutes_cap=0` (treinos easy)
- [ ] Validar conversão para FIT (workout_to_fit.mjs)
- [ ] Testar envio Telegram end-to-end
- [ ] Simular rejeições (JSON inválido, constraints violadas)
- [ ] Verificar logs em `/var/lib/ultra-coach/logs/`

**Comandos úteis:**
```bash
# Teste dry-run
run_coach_daily.sh --dry-run --verbose

# Teste real
run_coach_daily.sh --verbose

# Verificar último treino aceito
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT * FROM daily_plan_ai WHERE status='accepted' ORDER BY plan_date DESC LIMIT 1;"

# Verificar rejeições
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT plan_date, rejection_reason FROM daily_plan_ai WHERE status='rejected';"
```

---

#### 2. Setup Inicial do Atleta
**Objetivo:** Script para facilitar primeira configuração.

**Arquivo:** `bin/setup_athlete.sh`

```bash
#!/bin/bash
# setup_athlete.sh - Configuração inicial do atleta

# Perguntas interativas:
# - Nome do atleta
# - Athlete ID (default: zz)
# - HR max e rest
# - Objetivo (ultra 12h, 90km trail, etc)
# - Horas/semana disponíveis
# - Coach mode (conservative, moderate, aggressive)

# Ações:
# 1. Criar perfil em athlete_profile
# 2. Criar athlete_state inicial
# 3. (Opcional) Importar treinos históricos
# 4. Gerar relatório inicial
```

**Exemplo de uso:**
```bash
setup_athlete.sh

# Ou não-interativo:
setup_athlete.sh \
  --athlete-id "john_doe" \
  --name "John Doe" \
  --hr-max 185 \
  --hr-rest 52 \
  --goal "Ultra 12h - Junho 2026" \
  --weekly-hours 10 \
  --coach-mode moderate
```

---

#### 3. Automação via Cron
**Objetivo:** Pipeline rodando automaticamente todo dia.

**Arquivo:** `/etc/cron.d/ultra-coach`

```bash
# Ultra Coach - Crontab
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Coach diário às 5h da manhã (horário local)
0 5 * * * root source /etc/ultra-coach/env && /usr/local/bin/run_coach_daily.sh >> /var/lib/ultra-coach/logs/coach.log 2>&1

# Backup comprimido a cada 6 horas (mantém 14 dias)
0 */6 * * * root /usr/local/bin/backup_db.sh --compress --keep 56 >> /var/lib/ultra-coach/logs/backup.log 2>&1

# Sync InfluxDB a cada 2 horas (dados frescos)
0 */2 * * * root source /etc/ultra-coach/env && /usr/local/bin/sync_influx_to_sqlite.sh >> /var/lib/ultra-coach/logs/sync.log 2>&1

# Limpeza de logs antigos (mantém 30 dias)
0 3 * * 0 root find /var/lib/ultra-coach/logs -name "*.log" -mtime +30 -delete
```

**Instalação:**
```bash
# Copiar para cron.d
cp cron.d/ultra-coach /etc/cron.d/ultra-coach
chmod 0644 /etc/cron.d/ultra-coach

# Testar sintaxe
crontab -l

# Verificar logs
tail -f /var/lib/ultra-coach/logs/coach.log
```

---

#### 4. Documentação Básica
**Objetivo:** README.md completo para novos usuários.

**Estrutura sugerida:**

```markdown
# Ultra Coach

Sistema de treinos IA para ultra-endurance.

## Quick Start

1. Instalação
2. Configuração inicial
3. Primeiro treino
4. Automação

## Arquitetura

## Scripts Disponíveis

## Troubleshooting

## FAQ
```

**Seções importantes:**
- Pré-requisitos (Node.js, SQLite, jq, curl)
- Variáveis de ambiente obrigatórias (OPENAI_API_KEY)
- Como obter tokens (Telegram, n8n)
- Exemplos de configuração do InfluxDB
- Como interpretar logs
- Erros comuns e soluções

---

### 📊 Prioridade Média (Próxima iteração)

#### 5. Feedback Loop do Atleta
**Objetivo:** Capturar como o atleta se sentiu pós-treino.

**Migration:** `sql/migrations/002_workout_feedback.sql`
```sql
CREATE TABLE workout_feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  athlete_id TEXT NOT NULL,
  plan_date TEXT NOT NULL,
  completed BOOLEAN NOT NULL DEFAULT 0,
  actual_duration_min REAL,
  rpe INTEGER,  -- Rate of Perceived Exertion (1-10)
  feel TEXT CHECK(feel IN ('great', 'good', 'tired', 'bad')),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(athlete_id, plan_date),
  FOREIGN KEY (athlete_id) REFERENCES athlete_profile(athlete_id)
);
```

**Integração com Telegram:**
- Bot pergunta após treino: "Como foi o treino?"
- Botões inline: 😃 Great | 🙂 Good | 😓 Tired | 😞 Bad
- Pergunta RPE (1-10)
- Salva no banco

**Uso dos dados:**
- Ajustar readiness_score baseado em feedback
- Detectar overtraining precocemente
- Adaptar constraints dinamicamente

---

#### 6. Dashboard de Métricas
**Objetivo:** Visualização rápida do estado atual.

**Script:** `bin/dashboard.sh`
```bash
#!/bin/bash
# dashboard.sh - Mostra métricas do atleta

# Exibe:
# - Readiness/Fatigue (7 dias, gráfico ASCII)
# - Volume semanal (km, min, TRIMP)
# - Última atividade
# - Próximo treino planejado
# - Compliance (% treinos completados)
# - Progressão long run (últimos 4 sábados)
```

**Exemplo de saída:**
```
╔═══════════════════════════════════════════════════════╗
║         ULTRA COACH - Dashboard (zz)                  ║
╚═══════════════════════════════════════════════════════╝

📊 Estado Atual (2026-01-17)
  Readiness:  78/100  ████████████████░░░░
  Fatigue:    45/100  █████████░░░░░░░░░░░
  Coach Mode: moderate

📈 Semana Atual (15-21 Jan)
  Distância:  52.3 km
  Tempo:      6h 15min
  TRIMP:      342
  Quality:    1/2 treinos
  Long:       1/1 treinos

🏃 Última Atividade
  Data:       16/01 - 07:30
  Tipo:       Long Run
  Distância:  21.5 km (2h 15min)
  FC média:   138 bpm
  Feel:       Good 🙂

📅 Próximo Treino (17/01)
  Tipo:       Easy Run
  Duração:    70 min
  Status:     Aceito ✅

✅ Compliance (últimos 30 dias)
  Planejados: 15 treinos
  Completos:  13 treinos (87%)
```

---

#### 7. Relatórios Semanais
**Objetivo:** Email/Telegram toda segunda-feira resumindo semana anterior.

**Script:** `bin/weekly_report.sh`

```bash
#!/bin/bash
# weekly_report.sh - Relatório semanal

# Gera relatório com:
# - Resumo da semana (km, min, TRIMP)
# - Compliance (planejado vs executado)
# - Progressão (comparado com semanas anteriores)
# - Destaque: melhor treino da semana
# - Alerta: sinais de fadiga/monotonia
# - Recomendação: ajuste coach_mode se necessário
# - Preview semana seguinte

# Envia via Telegram formatado
```

**Agendamento:**
```bash
# Cron: toda segunda às 8h
0 8 * * 1 root source /etc/ultra-coach/env && /usr/local/bin/weekly_report.sh
```

---

#### 8. Periodização para Race Day
**Objetivo:** Taper automático conforme aproxima da prova.

**Migration:** `sql/migrations/003_race_planning.sql`
```sql
ALTER TABLE athlete_profile ADD COLUMN race_date TEXT;
ALTER TABLE athlete_profile ADD COLUMN race_distance_km REAL;

-- View útil
CREATE VIEW v_weeks_to_race AS
SELECT
  athlete_id,
  race_date,
  CAST((julianday(race_date) - julianday('now')) / 7.0 AS INT) AS weeks_to_race
FROM athlete_profile
WHERE race_date IS NOT NULL;
```

**Lógica de taper (em `run_coach_daily.sh`):**
```bash
# Se weeks_to_race < 3 e >= 1: taper (reduzir volume 20-30%)
# Se weeks_to_race = 0: semana da prova (só recovery + race day)
# Se weeks_to_race < 0: passou da prova (limpar race_date)

WEEKS_TO_RACE=$(sqlite3 "$DB" "SELECT weeks_to_race FROM v_weeks_to_race WHERE athlete_id='$ATHLETE';")

if [[ -n "$WEEKS_TO_RACE" && "$WEEKS_TO_RACE" -le 3 && "$WEEKS_TO_RACE" -ge 1 ]]; then
  # Ajusta constraints: reduz duration_max, hard_minutes_cap
  TAPER_FACTOR=0.7  # 30% redução
fi
```

---

### 🔧 Prioridade Baixa (Nice to have)

#### 9. Upload Automático para Garmin Connect
**Objetivo:** FIT vai direto pro calendário do Garmin.

**Bibliotecas:**
- Python: `python-garminconnect` ou `garth`
- Node.js: `garmin-connect` (não oficial)

**Exemplo (Python):**
```python
from garminconnect import Garmin

client = Garmin(email, password)
client.login()

# Upload workout FIT
with open('workout.fit', 'rb') as f:
    client.upload_activity(f)
```

**Integração:** Adicionar em `run_coach_daily.sh` após geração do FIT.

---

#### 10. Multi-atleta
**Objetivo:** Suportar vários atletas no mesmo servidor.

**Mudanças necessárias:**
- Scripts já suportam (via `$ATHLETE`)
- Criar wrapper: `bin/coach` que troca contexto
- Arquivo de configuração por atleta: `/etc/ultra-coach/athletes/john.env`

**Exemplo:**
```bash
# Rodar para atleta específico
coach --athlete john run_coach_daily.sh

# Trocar contexto
coach use john
coach run_coach_daily.sh
```

---

#### 11. Interface Web Simples
**Objetivo:** Dashboard visual + controle manual.

**Stack sugerida:**
- Backend: Flask (Python) ou FastAPI
- Frontend: HTML + Tailwind CSS + Alpine.js (ou HTMX)
- Auth: Básica (HTTP Basic Auth ou JWT simples)

**Features:**
- Página inicial: dashboard de métricas (mesmo que CLI)
- Calendário: treinos da semana
- Detalhes do treino: visualização do JSON formatado
- Botão "Aceitar/Rejeitar" treino manual
- Histórico de atividades (tabela)
- Gráficos: readiness/fatigue ao longo do tempo (Chart.js)
- Upload manual de FIT

**Endpoints:**
```
GET  /                    # Dashboard
GET  /workouts/today      # Treino do dia
GET  /workouts/:date      # Treino de data específica
POST /workouts/:date/accept
POST /workouts/:date/reject
GET  /activities          # Histórico
GET  /metrics             # API JSON para gráficos
```

---

#### 12. Análise Avançada
**Objetivo:** Insights automáticos sobre treinamento.

**Script:** `bin/analyze_training.sh`

**Análises:**

1. **Detecção de Overreaching:**
```sql
-- Alerta se readiness < 50 por 3+ dias consecutivos
-- E fatigue > 75 por 2+ dias consecutivos
```

2. **Recomendação de Deload Week:**
```sql
-- Se monotony > 2.0 e strain > 600 por 2 semanas
-- Sugere semana de volume 50%
```

3. **Correlação Volume x Performance:**
```sql
-- Analisa se aumentos de TRIMP > 20%/semana correlacionam com fadiga
-- Sugere taxa ideal de progressão
```

4. **Predição de Race Pace:**
```sql
-- Baseado em treinos de long run (pace em FC Z2)
-- Estima pace sustentável para 12h
```

**Saída:**
```
🔍 ANÁLISE DE TREINAMENTO (últimas 8 semanas)

⚠️  ALERTAS
  - Monotonia elevada (2.3) por 2 semanas consecutivas
  - Recomendação: deload week (-40% volume)

📈 TENDÊNCIAS
  - Volume semanal: crescimento constante (+8%/semana) ✅
  - Long run: progressão adequada (18km → 24km) ✅
  - FC em repouso: redução (-3 bpm) ✅ [adaptação positiva]

🎯 PREDIÇÃO RACE PACE (Ultra 12h)
  - Pace Z2 atual: 6:20 min/km @ 138 bpm
  - Pace estimado prova: 6:40-7:00 min/km
  - Distância prevista 12h: 85-90 km
```

---

### 🔒 Operação e Manutenção

#### 13. Alertas e Monitoramento
**Objetivo:** Ser notificado de problemas antes que afetem o atleta.

**Alertas importantes:**

1. **Pipeline falha 2x consecutivas:**
```bash
# Verificar se run_coach_daily.sh falhou
if [ $EXIT_CODE -ne 0 ]; then
  send_alert "Pipeline falhou: $EXIT_CODE"
fi
```

2. **Backup falha:**
```bash
# Monitorar logs de backup
if ! backup_db.sh; then
  send_alert "Backup falhou!"
fi
```

3. **InfluxDB sem dados novos por 48h:**
```sql
-- Verificar última atividade
SELECT MAX(start_at) FROM session_log;
-- Se > 48h, alertar
```

4. **Readiness crítico por 3 dias:**
```sql
-- Detectar overtraining
SELECT COUNT(*) FROM athlete_state_history
WHERE readiness_score < 40
  AND date(updated_at) >= date('now', '-3 days');
```

**Implementação:**
```bash
# bin/health_check.sh (roda via cron a cada 1h)
#!/bin/bash
# Verifica saúde do sistema e alerta se necessário

check_pipeline_health() { ... }
check_backup_health() { ... }
check_data_freshness() { ... }
check_athlete_wellbeing() { ... }

send_alert() {
  # Via Telegram, email ou PagerDuty
  curl -X POST "$WEBHOOK_URL" -d "alert=$1"
}
```

---

#### 14. Disaster Recovery
**Objetivo:** Procedimento claro para recuperação de falhas.

**Documentação:** `docs/disaster_recovery.md`

**Cenários:**

1. **Banco corrompido:**
```bash
# Restaurar último backup
cd /var/lib/ultra-coach/backups
latest_backup=$(ls -t coach_*.sqlite.gz | head -n1)
gunzip -c "$latest_backup" > /var/lib/ultra-coach/coach.sqlite

# Verificar integridade
sqlite3 /var/lib/ultra-coach/coach.sqlite "PRAGMA integrity_check;"
```

2. **Perda total do servidor:**
```bash
# Pré-requisito: backup offsite (rsync diário)
rsync -avz /var/lib/ultra-coach/backups/ backup-server:/backups/ultra-coach/

# Recuperação:
# 1. Reinstalar sistema
# 2. git clone ultra-coach
# 3. ./install.sh
# 4. rsync backups de volta
# 5. Restaurar último backup
# 6. Reconfigurar /etc/ultra-coach/env
```

3. **OpenAI API down:**
```bash
# Fallback manual: gerar treino baseado em template
# Ou usar backup de treino similar (mesmo tipo + constraints)
```

**Testes periódicos:**
```bash
# Testar restore mensalmente
backup_db.sh
init_db.sh --reset
# Restaurar backup manualmente
# Verificar dados
```

---

#### 15. Migração de Dados Históricos
**Objetivo:** Importar treinos antigos do Garmin/outras fontes.

**Script:** `bin/import_historical.sh`

```bash
#!/bin/bash
# import_historical.sh - Importa treinos históricos

# Fontes suportadas:
# 1. Export CSV do Garmin Connect
# 2. Export TCX/GPX bulk
# 3. Export Strava (via API)
# 4. Dump InfluxDB retroativo

# Para cada atividade:
# 1. Parse data, distância, duração, FC
# 2. Calcular TRIMP
# 3. Classificar (easy/quality/long)
# 4. INSERT INTO session_log
# 5. Recalcular athlete_state histórico
```

**Exemplo de uso:**
```bash
# Importar CSV do Garmin
import_historical.sh --source garmin_activities.csv --athlete zz

# Importar últimos 365 dias do InfluxDB
import_historical.sh --source influxdb --days 365 --athlete zz

# Dry-run (apenas mostra o que seria importado)
import_historical.sh --source strava --dry-run
```

**Recálculo de estado histórico:**
```sql
-- Após importar, recalcular weekly_state para todas as semanas
DELETE FROM weekly_state;

INSERT INTO weekly_state (athlete_id, week_start, quality_days, long_days, total_time_min, total_load, total_distance_km)
SELECT
  athlete_id,
  date(start_at, 'weekday 1', '-7 days') AS week_start,
  SUM(CASE WHEN tags LIKE '%quality%' THEN 1 ELSE 0 END) AS quality_days,
  SUM(CASE WHEN tags LIKE '%long%' THEN 1 ELSE 0 END) AS long_days,
  SUM(COALESCE(duration_min, 0)) AS total_time_min,
  SUM(COALESCE(trimp, 0)) AS total_load,
  SUM(COALESCE(distance_km, 0)) AS total_distance_km
FROM session_log
GROUP BY athlete_id, week_start;
```

---

## 📌 Recomendação de Ordem de Implementação

### **Esta Semana (17-24 Jan 2026):**
1. ✅ Teste end-to-end manual (1 dia)
2. ✅ Setup do perfil do atleta (meio dia)
3. ✅ Cron job básico (meio dia)

### **Próximas 2 Semanas (25 Jan - 07 Fev):**
4. ✅ Documentação README.md (1 dia)
5. ✅ Feedback loop básico (2 dias)
6. ✅ Dashboard CLI (1 dia)

### **Mês Seguinte (Fevereiro):**
7. ✅ Periodização race day (2 dias)
8. ✅ Relatórios semanais (1 dia)
9. ✅ Alertas básicos (1 dia)
10. ✅ Health checks (meio dia)

### **Backlog (quando tiver tempo):**
- Upload Garmin Connect
- Interface web
- Análise avançada
- Import histórico

---

## 📚 Referências

### Documentação Técnica
- SQLite JSON1: https://www.sqlite.org/json1.html
- Garmin FIT SDK: https://developer.garmin.com/fit/overview/
- InfluxDB v1 Query: https://docs.influxdata.com/influxdb/v1/query_language/
- OpenAI API: https://platform.openai.com/docs/api-reference

### Conceitos de Treinamento
- TRIMP (Training Impulse): Banister et al., 1975
- Monotonia e Strain: Foster (1998)
- Ultra-endurance training: Millet & Millet (2012)
- Taper strategies: Bosquet et al. (2007)

---

## 📝 Notas Finais

**Versão atual:** 1.0.0 (2026-01-17)
**Próxima revisão:** 2026-01-24
**Maintainer:** Claude + Usuário

**Como usar este documento:**
- Revisar semanalmente e marcar progresso
- Atualizar seção "Arquivos Modificados" conforme muda código
- Adicionar novos itens em "Próximos Passos" conforme surgem ideias
- Mover itens concluídos para "Mudanças Implementadas"

---

**🎯 Meta atual:** Sistema estável em produção gerando treinos diários até 2026-02-01.
