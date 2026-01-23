# Quick Start - Testes E2E Manuais

Guia rápido para executar testes End-to-End do Ultra Coach.

## 🚀 Setup Rápido (5 minutos)

### 1. Verificar Pré-requisitos

```bash
./bin/test_e2e_helper.sh check
```

**Resultado esperado:** Todos os ✅ verdes

Se algo falhar, veja [E2E_MANUAL_TEST_PLAN.md](E2E_MANUAL_TEST_PLAN.md) para troubleshooting.

## UI smoke test (Playwright)

Esse teste valida o dashboard de atividade e evita erros de JS antes de publicar:

```
make test-e2e-ui
```

Requisitos:
- `cd web && npm install`
- `cd web && npx playwright install --with-deps chromium`

---

### 2. Inicializar Database

```bash
./bin/test_e2e_helper.sh init
```

**O que faz:**
- Cria (ou recria) `/var/lib/ultra-coach/coach.sqlite`
- Aplica schema completo
- Insere policies padrão

⚠️ **ATENÇÃO:** Se já existe um database, será oferecida opção de backup antes de recriar.

---

### 3. Criar Atleta de Teste

```bash
./bin/test_e2e_helper.sh athlete
```

**O que faz:**
- Cria atleta `test_e2e`
- HR max: 185, HR rest: 48
- Readiness: 75, Fatigue: 50
- Coach mode: moderate

---

### 4. Inserir Dados de Teste

```bash
./bin/test_e2e_helper.sh data
```

**O que faz:**
- Insere 4 sessões de treino variadas (easy, quality, long)
- Últimos 7 dias
- Trigger atualiza `weekly_state` automaticamente

---

## ✅ Verificação Rápida

Ver estado do atleta:

```bash
./bin/test_e2e_helper.sh state
```

Ver histórico de sessões:

```bash
./bin/test_e2e_helper.sh history
```

---

## 🧪 Teste 1: Dry-Run (SEM custo)

Simula geração de treino sem chamar OpenAI:

```bash
./bin/test_e2e_helper.sh dry
```

**O que verificar:**
- ✅ Athlete state recalculado
- ✅ Workout type decidido (easy/quality/long/recovery)
- ✅ Constraints JSON exibido
- ✅ Mensagem "Modo --dry-run: NÃO chamando OpenAI"
- ✅ Sem erros

---

## 🤖 Teste 2: Geração Real (COM custo)

Gera treino chamando OpenAI API (consome créditos):

```bash
./bin/test_e2e_helper.sh run
```

**O que verificar:**
- ✅ Backup criado automaticamente
- ✅ OpenAI chamado (HTTP 200)
- ✅ Validação passou
- ✅ Workout salvo (status: accepted)
- ✅ FIT gerado (se configurado)
- ✅ Telegram enviado (se configurado)

Ver resultado:

```bash
./bin/test_e2e_helper.sh workout
```

---

## 📊 Testes Adicionais

### Testar Diferentes Tipos de Treino

Manipular estado para forçar tipos específicos:

**QUALITY (treino intervalado):**

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state
SET readiness_score = 82,
    fatigue_score = 35,
    days_since_quality = 4
WHERE athlete_id = 'test_e2e';

DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

./bin/test_e2e_helper.sh run
./bin/test_e2e_helper.sh workout
```

**Verificar:** Treino tem tiros/intervalos em Z3+

---

**LONG (treino longo):**

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state
SET readiness_score = 85,
    fatigue_score = 30,
    days_since_long = 8
WHERE athlete_id = 'test_e2e';

DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

./bin/test_e2e_helper.sh run
./bin/test_e2e_helper.sh workout
```

**Verificar:** Duração >= 90 min, run/walk

---

**RECOVERY (recuperação):**

```bash
sqlite3 /var/lib/ultra-coach/coach.sqlite <<EOF
UPDATE athlete_state
SET readiness_score = 58,
    fatigue_score = 78
WHERE athlete_id = 'test_e2e';

DELETE FROM daily_plan WHERE athlete_id='test_e2e' AND plan_date=date('now');
DELETE FROM daily_plan_ai WHERE athlete_id='test_e2e' AND plan_date=date('now');
EOF

./bin/test_e2e_helper.sh run
./bin/test_e2e_helper.sh workout
```

**Verificar:** Duração curta (30-50 min), ultra-leve (Z1)

---

## 🔄 Teste de Idempotência

Rodar coach duas vezes no mesmo dia:

```bash
./bin/test_e2e_helper.sh run   # Primeira vez
./bin/test_e2e_helper.sh run   # Segunda vez (deve detectar plano existente)
```

**Verificar:** Segunda execução não chama OpenAI, não sobrescreve plano

---

## 💾 Teste de Backup

```bash
# Criar backup
./bin/backup_db.sh --verbose

# Listar backups
ls -lh /var/lib/ultra-coach/backups/

# Verificar último backup
LATEST=$(ls -t /var/lib/ultra-coach/backups/*.sqlite | head -n1)
sqlite3 "$LATEST" "PRAGMA integrity_check;"
```

**Verificar:** Backup criado, integridade OK

---

## 🧹 Limpeza

Remover todos os dados de teste:

```bash
./bin/test_e2e_helper.sh cleanup
```

---

## ✅ Checklist Mínimo para Aprovação

Antes de colocar em produção, verificar que:

- [ ] `check` passou sem erros
- [ ] Database inicializado corretamente
- [ ] Atleta criado e dados inseridos
- [ ] Dry-run executou sem erros
- [ ] Geração real (OpenAI) funcionou
- [ ] Treino EASY gerado e aceito
- [ ] Treino QUALITY gerado e aceito
- [ ] Validação rejeitou Z3 quando `hard_cap=0` *(ver teste manual)*
- [ ] FIT file gerado (se configurado)
- [ ] Telegram enviado (se configurado)
- [ ] Idempotência funciona
- [ ] Backup cria arquivo válido
- [ ] Sem erros nos logs

---

## 📖 Documentação Completa

Para testes detalhados e troubleshooting, veja:

- **[E2E_MANUAL_TEST_PLAN.md](E2E_MANUAL_TEST_PLAN.md)** - Plano completo de testes (14 seções)
- **[../CLAUDE.md](../CLAUDE.md)** - Documentação do projeto
- **[README.md](README.md)** - Guia de testes unitários

---

## 🆘 Problemas Comuns

### "OPENAI_API_KEY não configurado"

```bash
# Editar arquivo de configuração
sudo nano /etc/ultra-coach/env

# Adicionar:
OPENAI_API_KEY=sk-your-key-here

# Recarregar
source /etc/ultra-coach/env
```

### "Database is locked"

```bash
# Verificar processos usando o DB
lsof /var/lib/ultra-coach/coach.sqlite

# Aguardar ou matar processo
```

### "FIT file não gerado"

```bash
# Verificar módulos Node.js
cd /opt/ultra-coach/fit && npm list @garmin/fitsdk

# Reinstalar se necessário
npm install
```

### "OpenAI HTTP 429 (Rate Limit)"

Aguardar alguns minutos. OpenAI tem limites de requisições por minuto.

---

## 🎯 Próximos Passos

Após testes bem-sucedidos:

1. **Configurar Cron** para execução diária
2. **Configurar Telegram** para notificações
3. **Monitorar logs** nos primeiros dias
4. **Ajustar coach_mode** baseado em feedback

Veja `progress.md` seção "Próximos Passos" para roadmap completo.
