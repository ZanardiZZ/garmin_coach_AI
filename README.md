# Ultra Coach

Ultra Coach gera treinos diarios para ultramaratona com base nas metricas do Garmin, combinando regras deterministicas com variacao controlada por IA. Inclui dashboard web, sincronizacao Garmin -> InfluxDB -> SQLite, chat com o coach (web/Telegram) e envio de treinos por Telegram.

## Como rodar

Instalacao em 1 comando:
```bash
curl -fsSL https://raw.githubusercontent.com/ZanardiZZ/garmin_coach_AI/main/install.sh | sudo bash
```

Depois da instalacao:
1) Abra o setup web: `http://<seu-host>:8080/setup`
2) Informe OpenAI, Telegram e Garmin Connect
3) Salve e aguarde o sync automatico (cron)

Execucao manual (se quiser testar):
```bash
# Rodar o pipeline diario
/opt/ultra-coach/bin/run_coach_daily.sh

# Sincronizar atividades e corpo
/opt/ultra-coach/bin/garmin_sync.sh
/opt/ultra-coach/bin/sync_influx_to_sqlite.sh
```

## Como usar

- Dashboard: `http://<seu-host>:8080/`
- Setup: `http://<seu-host>:8080/setup`
- Atividades: `http://<seu-host>:8080/activities`
- Detalhe: `http://<seu-host>:8080/activity/<activity_id>`
- Coach (chat/feedback): `http://<seu-host>:8080/coach`

Configuracoes e segredos ficam criptografados no SQLite (`config_kv`) com chave local em `~/.ultra-coach/secret.key`.

## Creditos

- Garmin sync baseado em https://github.com/arpanghosh8453/garmin-grafana (BSD-3-Clause)
- FIT SDK: https://github.com/garmin/fit-javascript-sdk

## Suporte / Duvidas

Abra uma issue no repo ou descreva o problema com logs em `/var/lib/ultra-coach/logs`.
