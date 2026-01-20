# Índice da Documentação - Ultra Coach

**Última atualização:** 2026-01-19
**Versão:** 1.1.0

Este documento serve como índice central de toda a documentação do projeto Ultra Coach.

---

## 📖 Estrutura da Documentação

```
/opt/ultra-coach/
├── README.md                           [TODO] Visão geral do projeto
├── CLAUDE.md                           [✅] Instruções para Claude Code
├── progress.md                         [✅] Histórico e roadmap
├── DOCUMENTATION_INDEX.md              [✅] Este arquivo
│
├── tests/
│   ├── README.md                       [✅] Guia completo de testes unitários
│   ├── IMPLEMENTATION_SUMMARY.md       [✅] Resumo da implementação de testes
│   ├── E2E_QUICK_START.md             [✅] Guia rápido para testes E2E
│   ├── E2E_MANUAL_TEST_PLAN.md        [✅] Plano detalhado de testes E2E
│   └── E2E_STATUS.md                  [✅] Status e checklist dos testes E2E
│
├── sql/
│   └── schema.sql                      [✅] Schema completo do database
│
└── templates/
    └── coach_prompt_ultra.txt          [✅] Prompt da OpenAI
```

---

## 🎯 Guia de Leitura Recomendado

### Para Entender o Projeto

**1. CLAUDE.md** (15-20 min) ⭐
- Visão geral do projeto e arquitetura
- Como o pipeline funciona
- Comandos comuns
- Design principles
- Seção de Testing (nova)

**2. progress.md** (20-30 min)
- Histórico completo de mudanças
- Bugs corrigidos e melhorias
- Roadmap de próximos passos
- Referências técnicas

### Para Testar o Sistema

**3. tests/E2E_QUICK_START.md** (5-10 min) ⭐ COMECE AQUI
- Setup rápido em 5 minutos
- Comandos prontos para usar
- Checklist mínimo
- Troubleshooting comum

**4. tests/E2E_MANUAL_TEST_PLAN.md** (30-40 min)
- Plano completo de testes
- 14 seções detalhadas
- Todos os cenários cobertos
- Verificações passo-a-passo

**5. tests/E2E_STATUS.md** (5 min)
- Status atual dos testes
- Checklist de execução
- Registro de resultados

### Para Desenvolver Testes

**6. tests/README.md** (20-30 min)
- Guia completo de testes unitários
- Como escrever testes BATS
- Como escrever testes Vitest
- Fixtures e mocks
- CI/CD e git hooks

**7. tests/IMPLEMENTATION_SUMMARY.md** (10-15 min)
- Resumo da implementação
- Estatísticas (126 testes, 31 arquivos)
- O que foi implementado vs. o que falta

### Para Entender o Database

**8. sql/schema.sql** (10-15 min)
- Schema completo
- 9 tabelas principais
- Triggers e views
- Comentários explicativos

---

## 📚 Documentação por Categoria

### 🏗️ Arquitetura

| Documento | Descrição | Tempo | Prioridade |
|-----------|-----------|-------|------------|
| CLAUDE.md | Visão geral técnica, pipeline, design | 15-20 min | ⭐⭐⭐ |
| progress.md | Histórico de mudanças e decisões | 20-30 min | ⭐⭐ |
| sql/schema.sql | Estrutura do database | 10-15 min | ⭐⭐ |

### 🧪 Testes

| Documento | Descrição | Tempo | Prioridade |
|-----------|-----------|-------|------------|
| tests/E2E_QUICK_START.md | Guia rápido para começar | 5-10 min | ⭐⭐⭐ |
| tests/E2E_MANUAL_TEST_PLAN.md | Plano completo de testes | 30-40 min | ⭐⭐⭐ |
| tests/E2E_STATUS.md | Status e checklist | 5 min | ⭐⭐ |
| tests/README.md | Testes unitários (dev) | 20-30 min | ⭐⭐ |
| tests/IMPLEMENTATION_SUMMARY.md | Resumo de implementação | 10-15 min | ⭐ |

### 🤖 IA e Prompts

| Documento | Descrição | Tempo | Prioridade |
|-----------|-----------|-------|------------|
| templates/coach_prompt_ultra.txt | Prompt da OpenAI | 10 min | ⭐⭐ |

### 🔧 Scripts e Ferramentas

| Script | Descrição | Quando Usar |
|--------|-----------|-------------|
| bin/test_e2e_helper.sh | Auxiliar para testes E2E | Ao testar manualmente |
| bin/run_coach_daily.sh | Pipeline principal | Geração diária de treinos |
| bin/sync_influx_to_sqlite.sh | Sync de dados Garmin | Import de atividades |
| bin/init_db.sh | Gerenciador de database | Setup inicial, migrations |
| bin/backup_db.sh | Sistema de backup | Backups manuais/automáticos |
| bin/push_coach_message.sh | Notificação Telegram | Envio de mensagens |

---

## 🎓 Trilhas de Aprendizado

### Trilha 1: "Quero Usar o Sistema"
**Tempo total:** ~1h

1. ✅ Ler CLAUDE.md (seção "Project Overview" e "Common Commands")
2. ✅ Ler tests/E2E_QUICK_START.md
3. ✅ Executar setup com test_e2e_helper.sh
4. ✅ Rodar primeiro teste (dry-run)
5. ✅ Rodar teste real (com OpenAI)

**Resultado:** Sistema funcionando e testado

---

### Trilha 2: "Quero Entender Como Funciona"
**Tempo total:** ~2h

1. ✅ Ler CLAUDE.md completo
2. ✅ Ler progress.md (seção "Arquitetura" e "Mudanças Implementadas")
3. ✅ Ler sql/schema.sql (estrutura das tabelas)
4. ✅ Explorar código dos scripts principais
5. ✅ Ler templates/coach_prompt_ultra.txt

**Resultado:** Compreensão profunda do sistema

---

### Trilha 3: "Quero Desenvolver/Modificar"
**Tempo total:** ~3h

1. ✅ Trilha 2 completa (entender como funciona)
2. ✅ Ler tests/README.md (guia de testes)
3. ✅ Ler tests/IMPLEMENTATION_SUMMARY.md
4. ✅ Estudar tests/unit/bash/*.bats (exemplos)
5. ✅ Estudar tests/unit/node/*.test.mjs (exemplos)
6. ✅ Ler CLAUDE.md (seção "Modifying the System")

**Resultado:** Pronto para contribuir com código

---

### Trilha 4: "Quero Validar Tudo"
**Tempo total:** ~4h

1. ✅ Trilha 1 completa (usar o sistema)
2. ✅ Ler tests/E2E_MANUAL_TEST_PLAN.md completo
3. ✅ Executar todos os 14 testes detalhados
4. ✅ Documentar resultados em E2E_STATUS.md
5. ✅ Rodar suite de testes unitários: `make test`
6. ✅ Verificar cobertura: `make coverage`

**Resultado:** Sistema completamente validado

---

## 📊 Estatísticas da Documentação

### Documentos Criados
- **Total:** 8 documentos principais
- **Linhas totais:** ~3,500 linhas
- **Tempo de leitura total:** ~3-4 horas

### Cobertura por Tema
- ✅ Arquitetura e design: 100%
- ✅ Testes (unit + E2E): 100%
- ✅ Scripts e comandos: 100%
- ✅ Database e schema: 100%
- ✅ IA e prompts: 100%
- ⚠️  README.md geral: 0% (TODO)

---

## 🔍 Busca Rápida

### "Como eu..."

**...inicio o sistema pela primeira vez?**
→ tests/E2E_QUICK_START.md

**...entendo a arquitetura?**
→ CLAUDE.md (seção "Architecture")

**...escrevo um teste?**
→ tests/README.md (seção "Escrevendo Testes")

**...modifico o código?**
→ CLAUDE.md (seção "Modifying the System")

**...adiciono uma nova constraint?**
→ CLAUDE.md (seção "To add a new constraint")

**...debug um problema?**
→ tests/E2E_MANUAL_TEST_PLAN.md (seção "Troubleshooting")

**...verifico o que mudou no código?**
→ progress.md (seção "Mudanças Implementadas")

**...configuro o cron?**
→ progress.md (seção "Automação via Cron")

**...entendo as tabelas do database?**
→ sql/schema.sql

**...modifico o prompt da IA?**
→ templates/coach_prompt_ultra.txt

---

## 📝 Checklist de Revisão

Use esta checklist para garantir que revisou o essencial:

### Básico (mínimo para usar o sistema)
- [ ] CLAUDE.md - Seções: Overview, Architecture, Common Commands
- [ ] tests/E2E_QUICK_START.md - Completo
- [ ] Executou `./bin/test_e2e_helper.sh help`

### Intermediário (entender o sistema)
- [ ] CLAUDE.md - Completo
- [ ] progress.md - Seções: Arquitetura, Mudanças, Próximos Passos
- [ ] sql/schema.sql - Estrutura das tabelas principais
- [ ] tests/E2E_MANUAL_TEST_PLAN.md - Seções 1-6 (testes básicos)

### Avançado (contribuir com código)
- [ ] Todo "Intermediário" acima
- [ ] tests/README.md - Completo
- [ ] tests/IMPLEMENTATION_SUMMARY.md
- [ ] Estudou exemplos de testes (*.bats e *.test.mjs)
- [ ] Leu código de pelo menos 2 scripts em bin/

### Expert (validação completa)
- [ ] Todo "Avançado" acima
- [ ] tests/E2E_MANUAL_TEST_PLAN.md - Todas as 14 seções
- [ ] Executou todos os testes E2E
- [ ] Executou `make test` (testes unitários)
- [ ] Revisou cobertura de código

---

## 🎯 Recomendação de Início

**Para começar HOJE:**

1. **Ler (15 min):**
   ```bash
   cat /opt/ultra-coach/CLAUDE.md | less
   # Focar em: Overview, Architecture, Common Commands
   ```

2. **Ler (10 min):**
   ```bash
   cat /opt/ultra-coach/tests/E2E_QUICK_START.md | less
   ```

3. **Executar (5 min):**
   ```bash
   ./bin/test_e2e_helper.sh check
   ```

4. **Próximo passo:**
   - Se check passou: seguir E2E_QUICK_START.md
   - Se check falhou: resolver issues e tentar novamente

**Tempo total:** ~30 min para estar pronto para testar

---

## 📞 Suporte e Referências

### Documentação Externa
- [SQLite JSON1](https://www.sqlite.org/json1.html)
- [Garmin FIT SDK](https://developer.garmin.com/fit/overview/)
- [InfluxDB v1 Query](https://docs.influxdata.com/influxdb/v1/query_language/)
- [OpenAI API](https://platform.openai.com/docs/api-reference)
- [BATS Documentation](https://bats-core.readthedocs.io/)
- [Vitest Documentation](https://vitest.dev/)

### Dentro do Projeto
- Issues/Bugs: (TODO: adicionar link do repo)
- Dúvidas técnicas: Ver troubleshooting em cada documento
- Sugestões: Ver progress.md seção "Próximos Passos"

---

## 🔄 Atualizações da Documentação

| Data | Documento | Mudança |
|------|-----------|---------|
| 2026-01-19 | DOCUMENTATION_INDEX.md | Criação inicial |
| 2026-01-19 | tests/E2E_*.md | Criação dos 3 documentos E2E |
| 2026-01-19 | tests/README.md | Criação do guia de testes unitários |
| 2026-01-19 | tests/IMPLEMENTATION_SUMMARY.md | Resumo da implementação |
| 2026-01-19 | CLAUDE.md | Adição da seção "Testing" |
| 2026-01-17 | progress.md | Documentação da refatoração completa |
| 2026-01-17 | CLAUDE.md | Criação inicial |

---

## ✅ Próximos Passos Documentação

### TODO
- [ ] Criar README.md principal do projeto
- [ ] Adicionar diagramas de arquitetura (ASCII art ou Mermaid)
- [ ] Documentar processo de deploy
- [ ] Criar guia de troubleshooting consolidado
- [ ] Adicionar exemplos de uso real (case studies)
- [ ] Documentar integrações (Telegram, n8n, Garmin)

### Em Consideração
- [ ] Wiki no GitHub
- [ ] Changelog automatizado
- [ ] API documentation (se expor API futuramente)
- [ ] Video tutorials

---

**Versão:** 1.1.0
**Status:** 🟢 Documentação core completa

**Sugestão:** Comece pela **Trilha 1** se quiser usar o sistema hoje, ou pela **Trilha 2** se quiser entender profundamente antes de testar.
