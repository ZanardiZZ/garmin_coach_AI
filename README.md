# Ultra Coach

Ultra Coach gera treinos diarios para ultramaratona com base nas metricas do Garmin, combinando regras deterministicas com variacao controlada por IA. Inclui dashboard web, sincronizacao Garmin -> InfluxDB -> SQLite, chat com o coach (web/Telegram) e dashboards Grafana prontos.

## Como rodar

Instalacao em 1 comando:
```bash
curl -fsSL https://raw.githubusercontent.com/ZanardiZZ/garmin_coach_AI/main/install.sh | sudo bash
```

Upgrade (sem perder dados):
```bash
curl -fsSL https://raw.githubusercontent.com/ZanardiZZ/garmin_coach_AI/main/install.sh | sudo bash -s -- --upgrade
```

Desinstalar (mantem dados):
```bash
sudo /opt/ultra-coach/bin/uninstall.sh
```

Desinstalar removendo dados e codigo:
```bash
sudo /opt/ultra-coach/bin/uninstall.sh --purge-data --remove-code
```

Depois da instalacao:
1) Abra o setup web: `http://<seu-host>:<PORT>/setup` (PORT fica no output do install ou em `/etc/ultra-coach/env`)
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

- Dashboard: `http://<seu-host>:<PORT>/`
- Setup: `http://<seu-host>:<PORT>/setup`
- Atividades: `http://<seu-host>:<PORT>/activities`
- Detalhe: `http://<seu-host>:<PORT>/activity/<activity_id>`
- Coach (chat/feedback): `http://<seu-host>:<PORT>/coach`
- Grafana: `http://<seu-host>:<PORT>/grafana`

Configuracoes e segredos ficam criptografados no SQLite (`config_kv`) com chave local em `~/.ultra-coach/secret.key`.

## Screenshots

![Dashboard](docs/screenshots/dashboard.png)
![Activities](docs/screenshots/activities.png)
![Activity Detail](docs/screenshots/activity-detail.png)
![Coach](docs/screenshots/coach.png)
![Setup](docs/screenshots/setup.png)

## Creditos

- Garmin sync baseado em https://github.com/arpanghosh8453/garmin-grafana (BSD-3-Clause)
- FIT SDK: https://github.com/garmin/fit-javascript-sdk

## Suporte / Duvidas

Abra uma issue no repo ou descreva o problema com logs em `/var/lib/ultra-coach/logs`.
