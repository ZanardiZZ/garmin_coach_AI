# Plano de Testes End-to-End Manuais - Ultra Coach

**Objetivo:** Validar que todo o pipeline funciona corretamente antes de colocar em produção.

**Data:** 2026-01-19
**Status:** 🟡 Em execução

---

## 📋 Pré-requisitos

### 1. Verificar Instalação

```bash
# Verificar que todos os binários estão instalados
command -v sqlite3 && echo "✅ SQLite" || echo "❌ SQLite FALTANDO"
command -v jq && echo "✅ jq" || echo "❌ jq FALTANDO"
command -v curl && echo "✅ curl" || echo "❌ curl FALTANDO"
command -v node && echo "✅ Node.js" || echo "❌ Node.js FALTANDO"
command -v bc && echo "✅ bc" || echo "❌ bc FALTANDO"

# Verificar Node.js >= 18
node_version=$(node --version | sed 's/v//' | cut -d. -f1)
if [[ "$node_version" -ge 18 ]]; then
  echo "✅ Node.js versão OK ($node_version)"
else
  echo "❌ Node.js versão inadequada ($node_version < 18)"
fi

# Verificar scripts estão no PATH
command -v run_coach_daily.sh && echo "✅ Scripts no PATH" || echo "❌ Scripts não encontrados"
```

### 2. Verificar Configuração

```bash
# Verificar arquivo de ambiente
if [[ -f /etc/ultra-coach/env ]]; then
  echo "✅ Arquivo /etc/ultra-coach/env existe"
  source /etc/ultra-coach/env

  # Verificar variáveis críticas (se não usar /setup web)
  [[ -n "$OPENAI_API_KEY" ]] && echo "✅ OPENAI_API_KEY configurado" || echo "❌ OPENAI_API_KEY FALTANDO"
  [[ -n "$INFLUX_URL" ]] && echo "✅ INFLUX_URL configurado" || echo "❌ INFLUX_URL FALTANDO"
  [[ -n "$TELEGRAM_BOT_TOKEN" ]] && echo "✅ TELEGRAM_BOT_TOKEN configurado" || echo "⚠️  TELEGRAM_BOT_TOKEN FALTANDO"
  [[ -n "$TELEGRAM_CHAT_ID" ]] && echo "✅ TELEGRAM_CHAT_ID configurado" || echo "⚠️  TELEGRAM_CHAT_ID FALTANDO"
  [[ -n "$ATHLETE" ]] && echo "✅ ATHLETE = $ATHLETE" || echo "⚠️  ATHLETE não configurado (usará 'zz')"
else
  echo "❌ Arquivo /etc/ultra-coach/env NÃO EXISTE"
fi
```

**Nota:** o caminho recomendado é configurar tudo via `http://<host>:8080/setup` (os segredos ficam criptografados no SQLite).

### 3. Verificar Estrutura de Diretórios

```bash
# Verificar diretórios necessários
for dir in /var/lib/ultra-coach/{logs,exports,backups}; do
  if [[ -d "$dir" ]]; then
    echo "✅ $dir existe"
  else
    echo "❌ $dir NÃO EXISTE"
  fi
done

# Verificar permissões de escrita
touch /var/lib/ultra-coach/test_write && rm /var/lib/ultra-coach/test_write && \
  echo "✅ Permissões de escrita OK" || \
  echo "❌ Sem permissão de escrita em /var/lib/ultra-coach"
```

---

## 🗄️ Teste 1: Inicialização do Database

### 1.1 Criar Database do Zero

```bash
cd /opt/ultra-coach

# Backup de DB existente (se houver)
if [[ -f /var/lib/ultra-coach/coach.sqlite ]]; then
  cp /var/lib/ultra-coach/coach.sqlite /var/lib/ultra-coach/coach.sqlite.backup-$(date +%Y%m%d_%H%M%S)
  echo "✅ Backup do DB existente criado"
fi

# Criar novo database
./bin/init_db.sh --reset
```

**Verificações:**
- [ ] Script executou sem erros
- [ ] Arquivo `/var/lib/ultra-coach/coach.sqlite` foi criado
- [ ] Mensagem "Database criado com sucesso"

### 1.2 Verificar Schema

```bash
# Listar todas as tabelas
sqlite3 /var/lib/ultra-coach/coach.sqlite ".tables"
```

**Esperado:**
```
athlete_profile       config_kv           coach_policy
athlete_state         weekly_state        session_log
body_comp_log         daily_plan          daily_plan_ai
coach_chat            athlete_feedback
```

**Verificações:**
- [ ] Todas as 11 tabelas existem
- [ ] Sem mensagens de erro

### 1.2.1 Seed mock para dashboard (opcional)

```bash
/opt/ultra-coach/bin/mock_seed.sh --reset
```

**Verificações:**
- [ ] `/coach` mostra histórico de conversa e feedback
- [ ] `/activities` lista atividades mock

### 1.3 Verificar Policies Padrão

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite "SELECT mode, readiness_floor, fatigue_cap FROM coach_policy;"
```

**Esperado:**
```
conservative|70|60
moderate|60|70
aggressive|50|80
```

**Verificações:**
- [ ] 3 policies carregadas
- [ ] Valores corretos

### 1.4 Verificar Triggers

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite "SELECT name FROM sqlite_master WHERE type='trigger';"
```

**Esperado:**
```
trg_session_log_update_weekly
```

**Verificações:**
- [ ] Trigger existe

---

## 👤 Teste 2: Criar Perfil do Atleta

### 2.1 Inserir Atleta de Teste

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
INSERT OR REPLACE INTO athlete_profile (
  athlete_id, name, hr_max, hr_rest, weight_kg, lt_hr, lt_pace_min_km, lt_power_w, goal_event, weekly_hours_target
)
VALUES (
  'test_e2e', 'Atleta Teste', 185, 48, 72.0, 165, 4.5, 320, 'Ultra 12h Test', 10.0
);
EOF
```

**Verificações:**
- [ ] Comando executou sem erro
- [ ] Atleta inserido

### 2.2 Verificar Atleta

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite "SELECT * FROM athlete_profile WHERE athlete_id='test_e2e';"
```

**Esperado:**
```
test_e2e|185|48|Ultra 12h Test|2026-06-15
```

**Verificações:**
- [ ] Dados corretos
- [ ] athlete_id = test_e2e

### 2.3 Criar Estado Inicial

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
INSERT OR REPLACE INTO athlete_state (
  athlete_id, readiness_score, fatigue_score, monotony, strain,
  weekly_load, weekly_distance_km, weekly_time_min,
  last_long_run_km, last_long_run_at, last_quality_at, coach_mode, updated_at
)
VALUES (
  'test_e2e', date('now'), 'moderate',
  75.0, 50.0, 1.2, 85.0,
  100.0, 95.0, 0.15,
  date('now', '-3 days'), date('now', '-6 days'), 3, 6
);
EOF
```

**Verificações:**
- [ ] Estado criado
- [ ] readiness = 75, fatigue = 50

---

## 📊 Teste 3: Sync do InfluxDB (Opcional)

**Nota:** Este teste requer que InfluxDB esteja acessível e configurado.

### 3.1 Testar Conexão com InfluxDB

```bash
# Source das variáveis
source /etc/ultra-coach/env

# Testar query simples
curl -sG "$INFLUX_URL" \
  --data-urlencode "db=$INFLUX_DB" \
  --data-urlencode "q=SHOW DATABASES" | jq .
```

**Verificações:**
- [ ] Resposta HTTP 200
- [ ] JSON válido retornado
- [ ] Database listado

### 3.2 Executar Sync (se InfluxDB disponível)

```bash
ATHLETE_ID=test_e2e ./bin/sync_influx_to_sqlite.sh
```

**Verificações:**
- [ ] Script executou sem erro
- [ ] Log mostra "Running activities import"
- [ ] Sessões importadas (se houver dados)

### 3.3 Verificar Dados Importados

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT COUNT(*) FROM session_log WHERE athlete_id='test_e2e';"
```

**Verificações:**
- [ ] Contagem >= 0
- [ ] Se > 0, dados foram importados

---

## 📥 Teste 4: Inserir Dados de Teste Manualmente

**Alternativa ao sync do InfluxDB para testes.**

### 4.1 Inserir Sessões de Treino

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
-- Sessão 1: Easy run (hoje -7 dias)
INSERT INTO session_log (
  athlete_id, activity_id, start_at, duration_min, distance_km, avg_hr,
  max_hr, avg_pace_min_km, trimp, tags, notes
)
VALUES (
  'test_e2e', date('now', '-7 days'), 60, 10.0, 145,
  100, 500, 'easy', 85.5, 'Easy recovery run'
);

-- Sessão 2: Quality (hoje -5 dias)
INSERT INTO session_log (
  athlete_id, activity_id, start_at, duration_min, distance_km, avg_hr,
  max_hr, avg_pace_min_km, trimp, tags, notes
)
VALUES (
  'test_e2e', date('now', '-5 days'), 75, 12.0, 165,
  180, 650, 'quality', 135.2, 'Intervals 6x5min Z3'
);

-- Sessão 3: Long run (hoje -3 dias)
INSERT INTO session_log (
  athlete_id, activity_id, start_at, duration_min, distance_km, avg_hr,
  max_hr, avg_pace_min_km, trimp, tags, notes
)
VALUES (
  'test_e2e', date('now', '-3 days'), 120, 20.0, 152,
  300, 1100, 'long', 168.4, 'Long run weekend'
);

-- Sessão 4: Easy (hoje -1 dia)
INSERT INTO session_log (
  athlete_id, activity_id, start_at, duration_min, distance_km, avg_hr,
  max_hr, avg_pace_min_km, trimp, tags, notes
)
VALUES (
  'test_e2e', date('now', '-1 days'), 45, 7.5, 142,
  80, 380, 'easy', 58.3, 'Short recovery'
);
EOF
```

**Verificações:**
- [ ] 4 sessões inseridas
- [ ] Sem erros

### 4.2 Verificar Sessões

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT start_at, duration_min, tags FROM session_log WHERE athlete_id='test_e2e' ORDER BY start_at;"
```

**Esperado:** Lista de 4 sessões com tags variadas (easy, quality, long)

**Verificações:**
- [ ] 4 linhas retornadas
- [ ] Datas corretas
- [ ] Tags variadas

### 4.3 Verificar Weekly State (Trigger)

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT week_start, quality_days, long_days, total_time_min, total_load, total_distance_km FROM weekly_state WHERE athlete_id='test_e2e';"
```

**Esperado:** Registro(s) mostrando agregação semanal

**Verificações:**
- [ ] Registro criado automaticamente (trigger)
- [ ] quality_days >= 1
- [ ] long_days >= 1
- [ ] total_time_min > 0

---

## 🎯 Teste 5: Geração de Treino - Modo Dry-Run

### 5.1 Dry-Run Básico

```bash
ATHLETE=test_e2e ./bin/run_coach_daily.sh --dry-run --verbose
```

**Observar output:**
- [ ] Backup NÃO foi criado (modo dry-run)
- [ ] Athlete state recalculado
- [ ] Workout type decidido (easy/quality/long/recovery)
- [ ] Constraints JSON exibido
- [ ] Mensagem "Modo --dry-run: NÃO chamando OpenAI"
- [ ] Database NÃO foi modificado

### 5.2 Verificar Constraints Gerados

O output deve mostrar algo como:

```json
{
  "allowed_type": "easy",
  "duration_min": 45,
  "duration_max": 75,
  "hard_minutes_cap": 0,
  "z2_hr_cap": 150,
  "z3_hr_floor": 155,
  ...
}
```

**Verificações:**
- [ ] JSON válido exibido
- [ ] `allowed_type` definido
- [ ] Ranges de duração lógicos
- [ ] `hard_minutes_cap` correto para tipo

### 5.3 Verificar Decisão de Workout Type

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT plan_date, workout_type, duration_min FROM daily_plan WHERE athlete_id='test_e2e' ORDER BY plan_date DESC LIMIT 1;"
```

**Verificações:**
- [ ] Registro criado em daily_plan
- [ ] workout_type lógico baseado em estado
- [ ] duration_min dentro do esperado

---

## 🤖 Teste 6: Geração de Treino - Chamada Real à OpenAI

⚠️ **ATENÇÃO:** Este teste consome créditos da API OpenAI.

### 6.1 Preparar Ambiente

```bash
# Verificar que API key está configurada
source /etc/ultra-coach/env
echo "OpenAI API Key (primeiros 10 chars): ${OPENAI_API_KEY:0:10}..."

# Verificar saldo (opcional, se tiver acesso à API de billing)
```

### 6.2 Executar Coach com Treino EASY

Primeiro, vamos forçar um treino EASY manipulando o estado:

```bash
# Ajustar para garantir treino EASY (baixa readiness)
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state
SET readiness_score = 72,
    fatigue_score = 55,
    coach_mode = 'moderate'
WHERE athlete_id = 'test_e2e';
EOF

# Rodar coach (REAL, não dry-run)
ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose
```

**Observar output:**
- [ ] Backup criado antes de execução
- [ ] Athlete state recalculado
- [ ] Decisão: workout_type provavelmente EASY
- [ ] Constraints gerados
- [ ] Chamada à OpenAI (pode demorar 5-15s)
- [ ] HTTP 200 recebido
- [ ] JSON de resposta recebido
- [ ] Validação passou (tipo, duração, intensidade)
- [ ] Workout salvo no database (status: accepted)
- [ ] FIT file gerado (se configurado)
- [ ] Mensagem enviada ao Telegram (se configurado)

### 6.3 Verificar Workout Aceito

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
SELECT
  plan_date,
  status,
  json_extract(ai_workout_json, '$.tipo') as tipo,
  json_extract(ai_workout_json, '$.duracao_total_min') as duracao,
  json_extract(ai_workout_json, '$.objetivo') as objetivo
FROM daily_plan_ai
WHERE athlete_id = 'test_e2e'
  AND plan_date = date('now')
  AND status = 'accepted';
EOF
```

**Verificações:**
- [ ] Registro encontrado com status='accepted'
- [ ] tipo = 'easy' (ou o esperado)
- [ ] duracao dentro do range de constraints
- [ ] objetivo faz sentido

### 6.4 Inspecionar JSON Completo

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT json(ai_workout_json) FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');" \
  | jq .
```

**Verificações:**
- [ ] JSON válido e bem formatado
- [ ] Tem campo `tipo`
- [ ] Tem campo `segmentos` (array)
- [ ] Cada segmento tem: ordem, tipo, duracao_min, descricao
- [ ] Tem campo `nutricao`
- [ ] Avisos fazem sentido

### 6.5 Verificar Arquivo FIT (se gerado)

```bash
# Listar FIT files
ls -lh /var/lib/ultra-coach/exports/*.fit

# Verificar header FIT
if [[ -f /var/lib/ultra-coach/exports/workout_test_e2e_*.fit ]]; then
  hexdump -C /var/lib/ultra-coach/exports/workout_test_e2e_*.fit | head -n 5
  # Bytes 8-11 devem ser ".FIT"
  echo "✅ FIT file gerado"
else
  echo "⚠️  FIT file não encontrado"
fi
```

**Verificações:**
- [ ] Arquivo .fit existe
- [ ] Tamanho > 0 bytes
- [ ] Header contém ".FIT"

---

## 🧪 Teste 7: Geração de Outros Tipos de Treino

### 7.1 Treino QUALITY

Manipular estado para forçar quality:

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state
SET readiness_score = 82,
    fatigue_score = 35,
    days_since_quality = 4
WHERE athlete_id = 'test_e2e';

-- Limpar plano de hoje para poder regenerar
DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

# Rodar em dia de semana (Ter/Qui se possível)
ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose
```

**Verificações:**
- [ ] workout_type decidido: quality
- [ ] hard_minutes_cap > 0 em constraints
- [ ] Treino gerado tem tiros/intervalos em Z3+
- [ ] Validação aceita Z3 (não rejeitou)

### 7.2 Treino LONG

Manipular estado e data para forçar long run:

```bash
# Verificar dia da semana
date +%A  # Se não for Sábado, ajustar comando abaixo

sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state
SET readiness_score = 85,
    fatigue_score = 30,
    days_since_long = 8
WHERE athlete_id = 'test_e2e';

DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

# Rodar em sábado (ou forçar com env var)
ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose
```

**Verificações:**
- [ ] workout_type decidido: long
- [ ] Duração >= 90 min
- [ ] Treino menciona run/walk ou progressivo
- [ ] Campo nutricao tem valores > 0

### 7.3 Treino RECOVERY

Manipular estado para forçar recovery:

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state
SET readiness_score = 58,
    fatigue_score = 78
WHERE athlete_id = 'test_e2e';

DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose
```

**Verificações:**
- [ ] workout_type decidido: recovery
- [ ] Duração curta (30-50 min)
- [ ] hard_minutes_cap = 0
- [ ] Treino ultra-leve (Z1 predominante)

---

## 🚫 Teste 8: Validações e Rejeições

### 8.1 Simular Resposta Inválida da OpenAI

Vamos criar um mock de resposta inválida e testar a validação.

**Criar arquivo de teste:**

```bash
cat > /tmp/test_invalid_workout.json <<'EOF'
{
  "tipo": "quality",
  "duracao_total_min": 60,
  "objetivo": "Treino com Z3 mas constraint proíbe",
  "descricao_curta": "60min com Z3",
  "segmentos": [
    {
      "ordem": 1,
      "tipo": "main",
      "duracao_min": 60,
      "descricao": "Inclui tiros em Z3",
      "intensidade": "Z3"
    }
  ],
  "avisos": [],
  "nutricao": {"carbs_g_per_h": 0, "fluids_ml_per_h": 400, "sodium_mg_per_h": 0}
}
EOF
```

**Testar validação diretamente:**

```bash
# Source das funções do run_coach_daily.sh
source /etc/ultra-coach/env
ATHLETE=test_e2e
PLAN_DATE=$(date +%Y-%m-%d)
DB=/var/lib/ultra-coach/coach.sqlite

# Criar constraints de EASY (hard_cap=0)
CONSTRAINTS_JSON='{
  "allowed_type": "easy",
  "duration_min": 45,
  "duration_max": 75,
  "hard_minutes_cap": 0,
  "z2_hr_cap": 150
}'

# Testar validação
ALLOWED_TYPE="easy"
HARD_CAP=0

# Validação deve REJEITAR
if jq -r '.segmentos[]?.intensidade // ""' /tmp/test_invalid_workout.json | grep -Eiq '(z3|z4)'; then
  echo "✅ Validação CORRETA: Detectou Z3 proibido quando hard_cap=0"
else
  echo "❌ Validação FALHOU: Não detectou Z3 proibido"
fi
```

**Verificações:**
- [ ] Validação detecta tipo incompatível
- [ ] Validação detecta Z3/Z4 quando hard_cap=0
- [ ] Validação detecta duração fora do range

### 8.2 Testar Rejeição Real (se possível)

Se a OpenAI ocasionalmente gerar resposta inválida (raro), verificar:

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT plan_date, status, rejection_reason FROM daily_plan_ai WHERE athlete_id='test_e2e' AND status='rejected';"
```

**Verificações:**
- [ ] Se houver rejeições, rejection_reason está preenchido
- [ ] Motivo é claro e específico

---

## 📤 Teste 9: Notificação Telegram

### 9.1 Verificar Configuração

```bash
source /etc/ultra-coach/env

echo "Webhook URL: ${WEBHOOK_URL:0:30}..."
```

### 9.2 Testar Push Manual

```bash
ATHLETE=test_e2e PLAN_DATE=$(date +%Y-%m-%d) ./bin/push_coach_message.sh
```

**Verificações:**
- [ ] Script executou sem erro
- [ ] Mensagem apareceu no Telegram (se configurado)
- [ ] Formatação markdown correta
- [ ] Workout details exibidos

### 9.3 Verificar Payload Enviado

Se webhook estiver configurado, verificar logs do n8n ou capturar request:

```bash
# Alternativa: testar com webhook.site
# WEBHOOK_URL=https://webhook.site/seu-uuid ./bin/push_coach_message.sh
# Verificar em webhook.site
```

---

## 💾 Teste 10: Backup e Recovery

### 10.1 Criar Backup Manual

```bash
./bin/backup_db.sh --verbose
```

**Verificações:**
- [ ] Backup criado em `/var/lib/ultra-coach/backups/`
- [ ] Nome formato: `coach_YYYYMMDD_HHMMSS.sqlite`
- [ ] Integridade verificada (PRAGMA integrity_check)

### 10.2 Backup Comprimido

```bash
./bin/backup_db.sh --compress --verbose
```

**Verificações:**
- [ ] Arquivo .sqlite.gz criado
- [ ] Tamanho menor que .sqlite original

### 10.3 Testar Restore

```bash
# Backup atual
cp /var/lib/ultra-coach/coach.sqlite /tmp/coach_before_restore.sqlite

# Restaurar backup mais recente
LATEST_BACKUP=$(ls -t /var/lib/ultra-coach/backups/*.sqlite 2>/dev/null | head -n1)

if [[ -n "$LATEST_BACKUP" ]]; then
  cp "$LATEST_BACKUP" /var/lib/ultra-coach/coach.sqlite
  echo "✅ Backup restaurado: $LATEST_BACKUP"

  # Verificar integridade
  sqlite3 /var/lib/ultra-coach/coach.sqlite "PRAGMA integrity_check;"
else
  echo "⚠️  Nenhum backup encontrado"
fi

# Restaurar original
cp /tmp/coach_before_restore.sqlite /var/lib/ultra-coach/coach.sqlite
```

**Verificações:**
- [ ] Restore bem-sucedido
- [ ] Integridade OK
- [ ] Dados intactos

### 10.4 Rotação de Backups

```bash
# Criar vários backups
for i in {1..5}; do
  ./bin/backup_db.sh --compress --quiet
  sleep 1
done

# Testar rotação (manter apenas 3)
./bin/backup_db.sh --compress --keep 3

# Verificar
ls -lh /var/lib/ultra-coach/backups/ | wc -l
```

**Verificações:**
- [ ] Apenas 3 backups mantidos (+ . e ..)
- [ ] Mais antigos foram deletados

---

## 🔄 Teste 11: Pipeline Completo End-to-End

### 11.1 Executar Pipeline Completo

```bash
# Limpar planos existentes de hoje
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

# Executar pipeline completo
ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose 2>&1 | tee /tmp/coach_pipeline_log.txt
```

**Verificar sequência:**
1. [ ] Backup automático criado
2. [ ] Athlete state recalculado
3. [ ] Weekly state atualizado (se houver sessões novas)
4. [ ] Workout type decidido
5. [ ] Constraints gerados
6. [ ] OpenAI chamado
7. [ ] Resposta validada
8. [ ] Workout salvo (status: accepted)
9. [ ] FIT gerado (se configurado)
10. [ ] Telegram enviado (se configurado)
11. [ ] Log estruturado ([timestamp][component][level])

### 11.2 Verificar Resultado Final

```bash
# Database
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
SELECT
  dp.plan_date,
  dp.workout_type,
  dp.duration_min,
  dpa.status,
  json_extract(dpa.ai_workout_json, '$.descricao_curta') as descricao
FROM daily_plan dp
JOIN daily_plan_ai dpa ON dp.athlete_id = dpa.athlete_id AND dp.plan_date = dpa.plan_date
WHERE dp.athlete_id = 'test_e2e'
  AND dp.plan_date = date('now');
EOF
```

**Esperado:**
```
2026-01-19|easy|60|accepted|60min Z1-Z2 regenerativa
```

**Verificações:**
- [ ] Registro em daily_plan
- [ ] Registro em daily_plan_ai com status='accepted'
- [ ] Workout JSON populado
- [ ] Descrição faz sentido

### 11.3 Verificar Logs

```bash
# Verificar arquivo de log (se logging para arquivo estiver configurado)
if [[ -f /var/lib/ultra-coach/logs/coach.log ]]; then
  tail -50 /var/lib/ultra-coach/logs/coach.log
fi

# Ou verificar output capturado
grep -E '\[ERR\]|\[WARN\]' /tmp/coach_pipeline_log.txt
```

**Verificações:**
- [ ] Nenhum erro crítico ([ERR])
- [ ] Warnings (se houver) são esperados

---

## 🔁 Teste 12: Idempotência

### 12.1 Rodar Coach Duas Vezes no Mesmo Dia

```bash
# Primeira execução
ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose

# Segunda execução (mesmo dia)
ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose
```

**Verificações:**
- [ ] Segunda execução detecta que plano já existe
- [ ] Não chama OpenAI novamente
- [ ] Não sobrescreve plano accepted
- [ ] Log indica "Plano já existe para hoje"

### 12.2 Verificar Database

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT COUNT(*) FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');"
```

**Esperado:** 1 (não duplicou)

**Verificações:**
- [ ] Apenas 1 registro
- [ ] Plano original intacto

---

## ⚠️ Teste 13: Cenários de Erro

### 13.1 OpenAI Offline (Simular)

```bash
# Temporariamente quebrar URL
export OPENAI_API_URL="https://api.openai.invalid/v1"

ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose
```

**Verificações:**
- [ ] Retry com backoff exponencial (3 tentativas)
- [ ] Falha após 3 tentativas
- [ ] Log de erro claro
- [ ] Exit code != 0

### 13.2 API Key Inválida

```bash
# Temporariamente usar key inválida
export OPENAI_API_KEY="sk-invalid-key-test"

ATHLETE=test_e2e ./bin/run_coach_daily.sh --verbose
```

**Verificações:**
- [ ] HTTP 401 ou 403
- [ ] Não faz retry (erro 4xx)
- [ ] Plano marcado como rejected
- [ ] rejection_reason preenchido

### 13.3 Database Locked

```bash
# Abrir conexão que bloqueia
sqlite3 /var/lib/ultra-coach/coach.sqlite &
SQLITE_PID=$!

# Tentar rodar coach (deve falhar ou esperar)
ATHLETE=test_e2e ./bin/run_coach_daily.sh

# Matar sqlite
kill $SQLITE_PID
```

**Verificações:**
- [ ] Comportamento graceful
- [ ] Mensagem de erro clara (se falhar)

---

## 📊 Teste 14: Validação de Dados

### 14.1 Verificar Cálculo de TRIMP

```bash
# Pegar uma sessão e verificar TRIMP
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
SELECT
  start_at,
  duration_min,
  avg_hr,
  trimp,
  -- Recalcular TRIMP manualmente
  duration_min *
  ((avg_hr - 48.0) / (185.0 - 48.0)) *
  0.64 *
  exp(1.92 * ((avg_hr - 48.0) / (185.0 - 48.0))) as trimp_recalc
FROM session_log
WHERE athlete_id = 'test_e2e'
LIMIT 1;
EOF
```

**Verificações:**
- [ ] trimp ~= trimp_recalc (diferença < 0.5)

### 14.2 Verificar Weekly State

```bash
# Comparar agregação manual vs trigger
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
SELECT
  'trigger' as source,
  total_time_min,
  total_load,
  quality_days,
  long_days
FROM weekly_state
WHERE athlete_id = 'test_e2e'
  AND week_start = date('now', 'weekday 1', '-7 days')

UNION ALL

SELECT
  'manual' as source,
  SUM(duration_min) as total_time_min,
  SUM(trimp) as total_load,
  SUM(CASE WHEN tags LIKE '%quality%' THEN 1 ELSE 0 END) as quality_days,
  SUM(CASE WHEN tags LIKE '%long%' THEN 1 ELSE 0 END) as long_days
FROM session_log
WHERE athlete_id = 'test_e2e'
  AND date(start_at) >= date('now', 'weekday 1', '-7 days')
  AND date(start_at) < date('now', 'weekday 1');
EOF
```

**Verificações:**
- [ ] Valores do trigger == valores manuais

---

## 📝 Checklist Final de Testes

### Componentes Individuais
- [ ] Database inicializa corretamente
- [ ] Atleta criado com sucesso
- [ ] Sync InfluxDB funciona (ou dados manuais inseridos)
- [ ] Triggers atualizam weekly_state
- [ ] Backup cria arquivos válidos
- [ ] Restore funciona

### Geração de Treino
- [ ] Dry-run mostra constraints corretos
- [ ] Treino EASY gerado e aceito
- [ ] Treino QUALITY gerado e aceito
- [ ] Treino LONG gerado e aceito
- [ ] Treino RECOVERY gerado e aceito

### Validações
- [ ] Rejeita tipo incompatível
- [ ] Rejeita Z3+ quando hard_cap=0
- [ ] Rejeita duração fora do range
- [ ] Rejeita padrões de repetição quando hard_cap=0

### FIT e Notificação
- [ ] FIT file gerado com header válido
- [ ] Telegram recebe notificação (se configurado)

### Robustez
- [ ] Idempotência: não regenera treino existente
- [ ] Retry em erros de rede
- [ ] Não retry em erro 4xx
- [ ] Logs estruturados e claros

### Performance
- [ ] Pipeline completo < 30s (depende da OpenAI)
- [ ] Database queries rápidas (< 1s)

---

## 🐛 Troubleshooting Comum

### Erro: "Database is locked"
```bash
# Verificar processos usando o DB
lsof /var/lib/ultra-coach/coach.sqlite

# Matar processos se necessário
# Ou esperar que terminem
```

### Erro: "OpenAI HTTP 429 (Rate Limit)"
```bash
# Aguardar alguns minutos e tentar novamente
# Ou verificar limites da conta OpenAI
```

### Erro: "No workout generated"
```bash
# Verificar se plano já existe hoje
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT * FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');"

# Deletar se necessário e retentar
```

### FIT não gerado
```bash
# Verificar se Node.js tem módulos instalados
cd /opt/ultra-coach/fit && npm list @garmin/fitsdk

# Reinstalar se necessário
npm install
```

---

## ✅ Conclusão dos Testes

Ao completar todos os testes acima, você terá validado:

1. ✅ Setup e configuração corretos
2. ✅ Database funcional com schema completo
3. ✅ Pipeline de sync de dados (InfluxDB ou manual)
4. ✅ Geração de treinos para todos os tipos
5. ✅ Validações de segurança funcionando
6. ✅ Conversão para FIT
7. ✅ Notificações
8. ✅ Backup e recovery
9. ✅ Idempotência e robustez
10. ✅ Tratamento de erros

**Próximo passo:** Automação via cron e monitoramento em produção.

---

**Data de execução:** ___________
**Executado por:** ___________
**Resultado geral:** [ ] ✅ Passou  [ ] ⚠️ Passou com avisos  [ ] ❌ Falhou

---

## 💬 Teste 12: Coach Chat e Feedback (Web/Telegram)

### 12.1 Web Chat

1) Acesse: `http://<host>:8080/coach`
2) Envie uma mensagem (ex: "Treino de ontem foi pesado")

Verificar no DB:
```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT role, message FROM coach_chat WHERE athlete_id='test_e2e' ORDER BY created_at DESC LIMIT 5;"
```

**Verificações:**
- [ ] Mensagem do usuário registrada
- [ ] Resposta do coach registrada

### 12.2 Feedback

1) No /coach, preencha feedback (percepcao, RPE, notas)

Verificar no DB:
```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT perceived, rpe, notes FROM athlete_feedback WHERE athlete_id='test_e2e' ORDER BY created_at DESC LIMIT 3;"
```

**Verificações:**
- [ ] Feedback salvo

### 12.3 Telegram Bot (opcional)

Enviar no Telegram:
```
/feedback hard 8 subida longa
```

**Verificar no DB:**
```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT perceived, rpe, notes FROM athlete_feedback WHERE athlete_id='test_e2e' ORDER BY created_at DESC LIMIT 3;"
```

### 12.4 Feedback nas constraints

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT json_extract(constraints_json, '$.feedback_recent') FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');"
```

**Verificações:**
- [ ] Feedback recente aparece no JSON de constraints
