# Status dos Testes E2E - Ultra Coach

**Data de criação:** 2026-01-19
**Status:** 🟡 Pronto para execução

---

## 📋 Documentos Criados

### 1. E2E_MANUAL_TEST_PLAN.md
**Plano completo de testes End-to-End**

- 14 seções de testes detalhados
- ~500 linhas de documentação
- Cobertura completa do pipeline

**Conteúdo:**
- Pré-requisitos e verificações
- Testes por componente (DB, sync, geração, FIT, notificação)
- Testes de validação e rejeição
- Testes de backup e recovery
- Testes de idempotência
- Cenários de erro
- Troubleshooting

### 2. E2E_QUICK_START.md
**Guia rápido para execução**

- Setup em 5 minutos
- Comandos prontos para copiar/colar
- Checklist mínimo para aprovação
- Troubleshooting comum

### 3. test_e2e_helper.sh
**Script auxiliar para facilitar testes**

**Comandos disponíveis:**
```bash
./bin/test_e2e_helper.sh check      # Verifica pré-requisitos
./bin/test_e2e_helper.sh init       # Inicializa database
./bin/test_e2e_helper.sh athlete    # Cria atleta de teste
./bin/test_e2e_helper.sh data       # Insere dados de teste
./bin/test_e2e_helper.sh dry        # Dry-run (sem OpenAI)
./bin/test_e2e_helper.sh run        # Geração real (com OpenAI)
./bin/test_e2e_helper.sh workout    # Mostra workout gerado
./bin/test_e2e_helper.sh state      # Mostra estado do atleta
./bin/test_e2e_helper.sh history    # Mostra histórico de sessões
./bin/test_e2e_helper.sh cleanup    # Remove dados de teste
```

---

## 🎯 Como Usar

### Opção 1: Guia Rápido (Recomendado para primeiro teste)

```bash
cd /opt/ultra-coach
cat tests/E2E_QUICK_START.md
```

Siga o passo-a-passo para setup inicial e primeiros testes.

### Opção 2: Plano Completo (Para validação abrangente)

```bash
cd /opt/ultra-coach
cat tests/E2E_MANUAL_TEST_PLAN.md
```

Execute todos os 14 testes detalhados para validação completa.

---

## ✅ Checklist de Execução

### Setup Inicial
- [ ] Ler E2E_QUICK_START.md
- [ ] Executar `./bin/test_e2e_helper.sh check`
- [ ] Executar `./bin/test_e2e_helper.sh init`
- [ ] Executar `./bin/test_e2e_helper.sh athlete`
- [ ] Executar `./bin/test_e2e_helper.sh data`

### Testes Básicos
- [ ] Dry-run executou sem erros
- [ ] Geração real (OpenAI) funcionou
- [ ] Workout foi aceito
- [ ] JSON válido e completo

### Testes de Tipos de Treino
- [ ] EASY gerado e validado
- [ ] QUALITY gerado com Z3+
- [ ] LONG gerado (>=90min)
- [ ] RECOVERY gerado (curto, Z1)

### Validações
- [ ] Rejeita Z3+ quando hard_cap=0
- [ ] Rejeita tipo incompatível
- [ ] Rejeita duração fora do range

### Robustez
- [ ] Idempotência: não regenera plano existente
- [ ] Backup funciona
- [ ] FIT gerado (se configurado)
- [ ] Telegram enviado (se configurado)

---

## 📊 Cobertura de Testes

| Componente | Cobertura | Status |
|------------|-----------|--------|
| Database init | 100% | ✅ Documentado |
| Athlete profile | 100% | ✅ Documentado |
| Session log + triggers | 100% | ✅ Documentado |
| Sync InfluxDB | Opcional | ✅ Documentado |
| Geração de treino (todos os tipos) | 100% | ✅ Documentado |
| Validações (3 camadas) | 100% | ✅ Documentado |
| FIT generation | 100% | ✅ Documentado |
| Telegram notification | 100% | ✅ Documentado |
| Backup/Recovery | 100% | ✅ Documentado |
| Idempotência | 100% | ✅ Documentado |
| Cenários de erro | 80% | ✅ Documentado |

---

## 🚀 Próximos Passos Após Testes

Uma vez que os testes E2E passarem:

### 1. Configurar Atleta Real
- Substituir `test_e2e` por athlete_id real
- Ajustar HR max/rest
- Definir objetivo e data da prova

### 2. Sincronizar Dados Reais
- Configurar InfluxDB (se usar garmin-grafana)
- Ou inserir histórico manual
- Executar `sync_influx_to_sqlite.sh`

### 3. Automação
- Configurar cron job diário
- Configurar Telegram para notificações
- Configurar backups periódicos

### 4. Monitoramento
- Verificar logs diariamente (primeira semana)
- Ajustar coach_mode se necessário
- Validar treinos gerados

---

## 📁 Arquivos Relacionados

```
tests/
├── E2E_MANUAL_TEST_PLAN.md    # Plano completo (este arquivo)
├── E2E_QUICK_START.md         # Guia rápido
├── E2E_STATUS.md              # Status (você está aqui)
└── README.md                  # Testes unitários

bin/
└── test_e2e_helper.sh         # Script auxiliar

progress.md                     # Roadmap do projeto
CLAUDE.md                       # Documentação técnica
```

---

## 📝 Registro de Execução

Use esta seção para registrar quando os testes foram executados:

| Data | Executor | Resultado | Notas |
|------|----------|-----------|-------|
| ____ | ________ | [ ] ✅ [ ] ⚠️ [ ] ❌ | |
| ____ | ________ | [ ] ✅ [ ] ⚠️ [ ] ❌ | |
| ____ | ________ | [ ] ✅ [ ] ⚠️ [ ] ❌ | |

**Legenda:**
- ✅ Passou completamente
- ⚠️ Passou com avisos/ajustes necessários
- ❌ Falhou (registrar detalhes nas notas)

---

## 🆘 Suporte

Em caso de problemas durante os testes:

1. **Consultar troubleshooting:**
   - E2E_QUICK_START.md (seção "Problemas Comuns")
   - E2E_MANUAL_TEST_PLAN.md (seção "Troubleshooting Comum")

2. **Verificar logs:**
   ```bash
   tail -50 /var/lib/ultra-coach/logs/coach.log
   ```

3. **Verificar database:**
   ```bash
   sqlite3 /var/lib/ultra-coach/coach.sqlite "PRAGMA integrity_check;"
   ```

4. **Limpar e recomeçar:**
   ```bash
   ./bin/test_e2e_helper.sh cleanup
   # Seguir E2E_QUICK_START.md desde o início
   ```

---

**Status atual:** 🟢 Documentação completa, pronto para execução

**Próximo passo:** Executar testes seguindo E2E_QUICK_START.md
