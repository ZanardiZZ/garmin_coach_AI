.PHONY: help test test-unit test-unit-bash test-unit-node test-integration test-e2e test-e2e-ui test-sql \
        test-bash test-node coverage coverage-node clean install-deps lint lint-bash lint-node

# Configuração
BATS := bats
BATS_OPTS := --recursive --print-output-on-failure
TESTS_DIR := tests
FIT_DIR := fit

help: ## Mostra esta ajuda
	@echo "Ultra-Coach - Comandos de Teste"
	@echo ""
	@echo "Uso: make [target]"
	@echo ""
	@echo "Targets disponíveis:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install-deps: ## Instala todas as dependências de teste
	@echo "Instalando dependências de teste..."
	@./tests/install_deps.sh

test: test-unit test-node test-sql ## Roda todos os testes (unit + node + sql)
	@echo ""
	@echo "✅ Todos os testes passaram!"

test-unit: test-unit-bash ## Roda testes unitários Bash

test-unit-bash: ## Roda testes unitários Bash
	@echo "Rodando testes unitários Bash..."
	@$(BATS) $(BATS_OPTS) $(TESTS_DIR)/unit/bash/

test-unit-node: ## Roda testes unitários Node.js
	@echo "Rodando testes unitários Node.js..."
	@cd $(FIT_DIR) && npm test -- tests/unit/node/

test-integration: ## Roda testes de integração
	@echo "Rodando testes de integração..."
	@$(BATS) $(BATS_OPTS) $(TESTS_DIR)/integration/

test-e2e: ## Roda testes end-to-end
	@echo "Rodando testes E2E..."
	@$(BATS) $(BATS_OPTS) $(TESTS_DIR)/e2e/

test-e2e-ui: ## Roda smoke test UI com Playwright (dashboard/activity)
	@echo "Rodando testes E2E UI..."
	@$(TESTS_DIR)/e2e_ui/run_activity_smoke.sh

test-sql: ## Roda testes SQL (schema, migrations, triggers)
	@echo "Rodando testes SQL..."
	@$(BATS) $(BATS_OPTS) $(TESTS_DIR)/sql/

test-bash: test-unit-bash test-integration test-e2e test-sql ## Roda todos os testes Bash

test-node: ## Roda todos os testes Node.js
	@echo "Rodando todos os testes Node.js..."
	@cd $(FIT_DIR) && npm test

coverage: coverage-node ## Gera relatório de cobertura

coverage-node: ## Gera relatório de cobertura Node.js
	@echo "Gerando relatório de cobertura Node.js..."
	@cd $(FIT_DIR) && npm run coverage
	@echo ""
	@echo "Relatório HTML disponível em: fit/coverage/index.html"

lint: lint-bash lint-node ## Roda linting em todo o código

lint-bash: ## Roda shellcheck em scripts Bash
	@echo "Rodando shellcheck..."
	@find bin/ -type f -name "*.sh" -exec shellcheck {} +
	@find tests/ -type f -name "*.bash" -exec shellcheck {} + 2>/dev/null || true

lint-node: ## Roda ESLint em código Node.js
	@echo "Rodando ESLint..."
	@cd $(FIT_DIR) && npx eslint *.mjs || true

clean: ## Remove arquivos temporários e de cobertura
	@echo "Limpando arquivos temporários..."
	@rm -rf coverage/
	@rm -rf $(FIT_DIR)/coverage/
	@rm -rf $(FIT_DIR)/.vitest/
	@rm -f /tmp/test*.sqlite /tmp/*.json
	@rm -f $(TESTS_DIR)/fixtures/databases/*.sqlite
	@echo "Limpeza concluída"

# Atalhos convenientes
unit: test-unit ## Alias para test-unit
integration: test-integration ## Alias para test-integration
e2e: test-e2e ## Alias para test-e2e
sql: test-sql ## Alias para test-sql
