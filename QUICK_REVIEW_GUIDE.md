# Guia de Revisão Rápida - Ultra Coach
## 30 Minutos para Entender e Testar

**Objetivo:** Revisar o essencial e estar pronto para executar testes em 30 minutos.

---

## ⏱️ Cronograma

- **0-10 min:** Highlights do CLAUDE.md
- **10-20 min:** Highlights do E2E_QUICK_START.md
- **20-25 min:** Verificar pré-requisitos
- **25-30 min:** Primeiro teste (dry-run)

---

## 📖 PARTE 1: CLAUDE.md - Highlights (10 min)

### O Que é o Ultra Coach?

Sistema automatizado de treinos de ultra-endurance que:

1. **Sincroniza** dados do Garmin via InfluxDB
2. **Analisa** estado do atleta (fadiga, prontidão)
3. **Decide** tipo de treino (easy/quality/long/recovery)
4. **Gera** treino detalhado via OpenAI com constraints
5. **Valida** se treino respeita regras de segurança
6. **Converte** para FIT (Garmin)
7. **Notifica** via Telegram

### Pipeline Simplificado

```
Garmin → InfluxDB → SQLite → Análise Estado → Decisão Treino
                                                      ↓
Telegram ← FIT ← Validação ← OpenAI (com constraints)
```

### Componentes Principais

**Scripts em `/opt/ultra-coach/bin/`:**
- `run_coach_daily.sh` - Orquestrador principal (roda diariamente)
- `sync_influx_to_sqlite.sh` - Importa atividades do Garmin
- `init_db.sh` - Gerencia database e migrations
- `backup_db.sh` - Sistema de backup
- `push_coach_message.sh` - Envia para Telegram

**Database:** `/var/lib/ultra-coach/coach.sqlite`
- 9 tabelas principais
- Trigger automático para weekly_state
- TRIMP-based load management

**Node.js:** `/opt/ultra-coach/fit/workout_to_fit.mjs`
- Converte JSON → FIT file
- Compatível com Garmin

### Comandos Essenciais

```bash
# Testar sem chamar OpenAI
run_coach_daily.sh --dry-run --verbose

# Gerar treino real
run_coach_daily.sh --verbose

# Sincronizar dados do Garmin
ATHLETE_ID=zz sync_influx_to_sqlite.sh

# Backup manual
backup_db.sh --compress

# Inicializar database
init_db.sh

# Aplicar migrations
init_db.sh --migrate
```

### Lógica de Decisão de Treino

**RECOVERY** se:
- readiness_score < readiness_floor (ex: 65)
- OU fatigue_score > fatigue_cap (ex: 70)

**LONG** se:
- É fim de semana (Sáb/Dom)
- E readiness OK
- E não excede max_long_week

**QUALITY** se:
- É dia de semana (Ter/Qui)
- E readiness OK
- E quality_days < max_hard_days_week

**EASY** caso contrário

### Validação (3 camadas quando hard_cap=0)

Quando treino é EASY ou RECOVERY (`hard_minutes_cap=0`):

1. **Regex scan:** Detecta palavras proibidas (z3, z4, tiro, limiar, vo2)
2. **Campo intensity:** Verifica segmentos não têm Z3+
3. **Padrões:** Detecta repetições tipo "10x1000" ou "6x5min"

Se qualquer validação falhar → treino REJEITADO

### Configuração

Arquivo: `/etc/ultra-coach/env`

**Obrigatório:**
- `OPENAI_API_KEY` - Chave da API OpenAI
- `ATHLETE` - ID do atleta (default: zz)

**Opcional:**
- `INFLUX_URL` - URL do InfluxDB (se usar sync)
- `WEBHOOK_URL` - Para notificações Telegram
- `MODEL` - Modelo OpenAI (default: gpt-5)

### Design Principles

1. **Idempotência** - Scripts podem ser re-executados
2. **Safety First** - Backups antes de operações críticas
3. **Separation of Concerns** - Bash/SQL/IA/Node.js cada um faz sua parte
4. **TRIMP-Based** - Load management científico

---

## 🧪 PARTE 2: E2E_QUICK_START.md - Highlights (10 min)

### Setup Rápido (5 comandos)

```bash
# 1. Verificar pré-requisitos
./bin/test_e2e_helper.sh check

# 2. Inicializar database
./bin/test_e2e_helper.sh init

# 3. Criar atleta de teste
./bin/test_e2e_helper.sh athlete

# 4. Inserir dados de teste
./bin/test_e2e_helper.sh data

# 5. Ver estado
./bin/test_e2e_helper.sh state
```

### Teste 1: Dry-Run (SEM custo)

```bash
./bin/test_e2e_helper.sh dry
```

**O que verificar:**
- ✅ Athlete state recalculado
- ✅ Workout type decidido
- ✅ Constraints JSON exibido
- ✅ Mensagem "NÃO chamando OpenAI"
- ✅ Sem erros

### Teste 2: Geração Real (COM custo OpenAI)

```bash
./bin/test_e2e_helper.sh run
```

**O que verificar:**
- ✅ Backup criado
- ✅ OpenAI chamado (HTTP 200)
- ✅ Validação passou
- ✅ Workout salvo (status: accepted)

**Ver resultado:**
```bash
./bin/test_e2e_helper.sh workout
```

### Comandos do Helper

```bash
./bin/test_e2e_helper.sh check     # Verifica pré-requisitos
./bin/test_e2e_helper.sh init      # Inicializa DB
./bin/test_e2e_helper.sh athlete   # Cria atleta teste
./bin/test_e2e_helper.sh data      # Insere sessões
./bin/test_e2e_helper.sh dry       # Dry-run
./bin/test_e2e_helper.sh run       # Geração real
./bin/test_e2e_helper.sh workout   # Mostra workout
./bin/test_e2e_helper.sh state     # Mostra estado
./bin/test_e2e_helper.sh history   # Mostra histórico
./bin/test_e2e_helper.sh cleanup   # Remove dados teste
```

### Testar Diferentes Tipos

**Forçar QUALITY:**
```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state SET readiness_score = 82, fatigue_score = 35 WHERE athlete_id = 'test_e2e';
DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

./bin/test_e2e_helper.sh run
```

**Forçar RECOVERY:**
```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state SET readiness_score = 58, fatigue_score = 78 WHERE athlete_id = 'test_e2e';
DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

./bin/test_e2e_helper.sh run
```

### Checklist Mínimo

Antes de considerar validado:

- [ ] `check` passou sem erros
- [ ] Database inicializado
- [ ] Atleta e dados inseridos
- [ ] Dry-run executou sem erros
- [ ] Geração real funcionou
- [ ] Treino EASY aceito
- [ ] Treino QUALITY aceito (com Z3+)
- [ ] Idempotência: segunda execução não regenera
- [ ] Backup funciona

### Problemas Comuns

**"OPENAI_API_KEY não configurado"**
```bash
sudo nano /etc/ultra-coach/env
# Adicionar: OPENAI_API_KEY=sk-your-key
source /etc/ultra-coach/env
```

**"Database is locked"**
```bash
lsof /var/lib/ultra-coach/coach.sqlite
# Aguardar ou matar processo
```

**"FIT file não gerado"**
```bash
cd /opt/ultra-coach/fit && npm install
```

---

## ✅ PARTE 3: Verificação Prática (5 min)

### Passo 1: Verificar Pré-requisitos

```bash
cd /opt/ultra-coach
./bin/test_e2e_helper.sh check
```

**Esperado:**
```
✅ sqlite3 instalado
✅ jq instalado
✅ curl instalado
✅ node instalado
✅ bc instalado
✅ Node.js versão OK
✅ Scripts no PATH
✅ Arquivo /etc/ultra-coach/env existe
✅ OPENAI_API_KEY configurado
✅ Todos os diretórios existem
✅ Todos os pré-requisitos OK!
```

**Se algo falhar:**
- Instalar dependências faltantes
- Configurar `/etc/ultra-coach/env`
- Criar diretórios necessários

### Passo 2: Verificar Configuração

```bash
source /etc/ultra-coach/env
echo "✅ OPENAI_API_KEY: ${OPENAI_API_KEY:0:10}..."
echo "✅ ATHLETE: $ATHLETE"
echo "✅ DB: $ULTRA_COACH_DB"
```

### Passo 3: Verificar Database

```bash
# Se já existe database
ls -lh /var/lib/ultra-coach/coach.sqlite

# Ver tabelas
sqlite3 /var/lib/ultra-coach/coach.sqlite ".tables"

# Verificar integridade
sqlite3 /var/lib/ultra-coach/coach.sqlite "PRAGMA integrity_check;"
```

---

## 🚀 PARTE 4: Primeiro Teste (5 min)

### Teste Dry-Run (recomendado primeiro)

```bash
# Setup se ainda não fez
./bin/test_e2e_helper.sh init
./bin/test_e2e_helper.sh athlete
./bin/test_e2e_helper.sh data

# Dry-run
./bin/test_e2e_helper.sh dry
```

**O que observar no output:**

1. **Athlete State:**
   ```
   [INFO] Readiness: 75.0
   [INFO] Fatigue: 50.0
   [INFO] Coach mode: moderate
   ```

2. **Decisão:**
   ```
   [INFO] Workout type decided: easy
   [INFO] Duration range: 45-75 min
   ```

3. **Constraints:**
   ```json
   {
     "allowed_type": "easy",
     "duration_min": 45,
     "duration_max": 75,
     "hard_minutes_cap": 0,
     ...
   }
   ```

4. **Confirmação:**
   ```
   [INFO] Modo --dry-run: NÃO chamando OpenAI
   ```

**✅ Sucesso se:**
- Sem erros [ERR]
- Decisão lógica baseada em estado
- Constraints válidos

---

## 📊 Resumo Final

### Você Agora Sabe:

✅ **O que é** o Ultra Coach e como funciona
✅ **Pipeline completo** (Garmin → IA → FIT → Telegram)
✅ **Lógica de decisão** de tipo de treino
✅ **Validações** de segurança (3 camadas)
✅ **Comandos principais** para operar
✅ **Como testar** (dry-run e real)
✅ **Onde está** cada coisa (scripts, DB, configs)

### Próximos Passos:

1. **Agora (0-5 min):**
   ```bash
   ./bin/test_e2e_helper.sh check
   ```

2. **Se check passou (5-10 min):**
   ```bash
   ./bin/test_e2e_helper.sh init
   ./bin/test_e2e_helper.sh athlete
   ./bin/test_e2e_helper.sh data
   ./bin/test_e2e_helper.sh dry
   ```

3. **Se dry-run passou (10-15 min):**
   ```bash
   ./bin/test_e2e_helper.sh run     # ⚠️ Consome créditos OpenAI
   ./bin/test_e2e_helper.sh workout  # Ver resultado
   ```

4. **Depois dos testes:**
   - Validar outros tipos (quality, long, recovery)
   - Testar idempotência
   - Configurar atleta real
   - Automatizar com cron

---

## 🆘 Se Algo Der Errado

**Erro no check:**
- Ver troubleshooting em E2E_QUICK_START.md
- Instalar dependências faltantes
- Configurar env vars

**Erro no init:**
- Verificar permissões em /var/lib/ultra-coach
- Ver logs de erro
- Tentar com sudo se necessário

**Erro no dry-run:**
- Verificar que database foi criado
- Verificar que atleta existe
- Ver logs para detalhes

**Erro no run (OpenAI):**
- Verificar API key válida
- Verificar saldo OpenAI
- Ver rejection_reason no database

---

## 📚 Documentação Completa

Para ir além desta revisão rápida:

- **DOCUMENTATION_INDEX.md** - Índice completo
- **CLAUDE.md** - Documentação técnica completa
- **tests/E2E_MANUAL_TEST_PLAN.md** - 14 testes detalhados
- **progress.md** - Histórico e roadmap
- **tests/README.md** - Testes unitários

---

**⏱️ Tempo total desta revisão:** 30 minutos

**Status após revisar:** 🟢 Pronto para testar!

**Próxima ação:** Executar `./bin/test_e2e_helper.sh check`
