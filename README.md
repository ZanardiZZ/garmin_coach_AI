# Ultra Coach

Sistema para gerar treinos diarios (ultra endurance) com:
- decisao deterministica (regras + estado semanal)
- IA apenas para variacao controlada (constraints)
- persistencia em SQLite
- export opcional para FIT (workout) e envio via Telegram

## Estrutura
- `/opt/ultra-coach` (codigo)
- `/var/lib/ultra-coach` (dados: coach.sqlite, logs, exports, backups)
- symlinks em `/usr/local/bin` apontando para `/opt/ultra-coach/bin`

## Instalacao (1 comando)
```bash
curl -fsSL https://raw.githubusercontent.com/ZanardiZZ/garmin_coach_AI/main/install.sh | sudo bash
```

Depois da instalacao, abra o wizard:
```
http://<seu-host>:8080/setup
```

## Quick Start
```bash
# 1) Inicializar banco (primeira vez)
/opt/ultra-coach/bin/init_db.sh

# 2) Configurar ambiente
sudo nano /etc/ultra-coach/env

# 3) Criar atleta
/opt/ultra-coach/bin/setup_athlete.sh

# 4) Rodar pipeline (teste manual)
/opt/ultra-coach/bin/run_coach_daily.sh --verbose
```

## Configuracao (env)
Arquivo central: `/etc/ultra-coach/env` (carregado pelos scripts e pelo cron).

Variaveis principais:
- `OPENAI_API_KEY` (obrigatorio)
- `MODEL` (default: gpt-5)
- `ULTRA_COACH_PROJECT_DIR`, `ULTRA_COACH_DATA_DIR`, `ULTRA_COACH_DB`, `ULTRA_COACH_PROMPT_FILE`, `ULTRA_COACH_FIT_DIR`
- `INFLUX_URL`, `INFLUX_DB`, `INFLUX_USER`, `INFLUX_PASS` (sync, defaults locais)
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` (envio via bot)

Exemplo minimo:
```bash
export ULTRA_COACH_PROJECT_DIR="/opt/ultra-coach"
export ULTRA_COACH_DATA_DIR="/var/lib/ultra-coach"
export ULTRA_COACH_DB="/var/lib/ultra-coach/coach.sqlite"
export ULTRA_COACH_PROMPT_FILE="/opt/ultra-coach/templates/coach_prompt_ultra.txt"
export ULTRA_COACH_FIT_DIR="/opt/ultra-coach/fit"

export OPENAI_API_KEY="SUA_CHAVE"
export MODEL="gpt-5"

export INFLUX_URL="http://localhost:8086/query"
export INFLUX_DB="GarminStats"
export INFLUX_USER=""
export INFLUX_PASS=""

export TELEGRAM_BOT_TOKEN="SEU_TOKEN"
export TELEGRAM_CHAT_ID="SEU_CHAT_ID"
# WEBHOOK_URL nao e necessario (envio direto via Telegram bot)
```

## Configuracao via Web (preferido)
O wizard web salva as configuracoes no SQLite (tabela `config_kv`) com criptografia
AES-256-GCM. A chave local fica em `~/.ultra-coach/secret.key`.

Ao salvar pelo wizard, os scripts carregam os valores com:
```
node /opt/ultra-coach/bin/config_env.mjs
```

## Garmin Connect (sem docker)
Importamos a parte minima do projeto `garmin-grafana` (BSD-3-Clause) para
sincronizar dados Garmin -> InfluxDB sem dependencias de Docker.

Script:
- `bin/garmin_sync.py` (wrapper: `bin/garmin_sync.sh`)

Variaveis (salvas via wizard):
- `GARMINCONNECT_EMAIL`
- `GARMINCONNECT_PASSWORD`
- `GARMINCONNECT_IS_CN`
- `GARMIN_TOKEN_DIR`
- `GARMIN_SYNC_DAYS` (max 180)
- `GARMIN_FETCH_ACTIVITY_DETAILS` (true/false)

Detalhamento:
- Quando ativado, o sync grava pontos detalhados (GPS/FC/velocidade/etc) em `ActivityGPS` no Influx
- Usado pela pagina `/activity/:id` para mapa e graficos

Dependencias Python:
```bash
python3 -m venv /opt/ultra-coach/.venv
/opt/ultra-coach/.venv/bin/pip install garminconnect influxdb garth fitparse
```

Creditos: https://github.com/arpanghosh8453/garmin-grafana (BSD 3-Clause).

## Scripts
- `bin/init_db.sh`: cria/verifica banco e migrations
- `bin/setup_athlete.sh`: cria/atualiza atleta
- `bin/run_coach_daily.sh`: pipeline diario completo
- `bin/sync_influx_to_sqlite.sh`: importa dados do Influx
- `bin/garmin_sync.sh`: coleta Garmin -> Influx (sem Docker)
- `bin/send_weekly_plan.sh`: envia resumo semanal via Telegram
- `bin/backup_db.sh`: backup e rotacao
- `bin/push_coach_message.sh`: envia treino via webhook
- `bin/debug_coach.sh`: utilitarios de debug

## Cron
Exemplo de jobs (instalado em `/etc/cron.d/ultra-coach`):
- coach diario: 5h
- backup a cada 6h
- sync Influx a cada 2h
- limpeza de logs semanal
- webserver no boot (@reboot)
- resumo semanal a cada 5 min (verifica dia/horario configurado)

## Web Dashboard
Stack: Node + Express + EJS.

Instalacao:
```bash
cd /opt/ultra-coach/web
npm install
```

Execucao manual:
```bash
PORT=8080 ATHLETE=zz /usr/bin/node /opt/ultra-coach/web/app.js
```

Rotas principais:
- `/` dashboard
- `/activities` lista de atividades
- `/activity/:id` detalhe com mapa e graficos
- `/setup` configuracao

Auto-start via cron (instalado):
```
@reboot root source /etc/ultra-coach/env && cd /opt/ultra-coach/web && /usr/bin/node app.js >> /var/lib/ultra-coach/logs/web.log 2>&1
```

Autenticacao basica (opcional) via `/etc/ultra-coach/env`:
```
export PORT="8080"
export WEB_USER="seu_usuario"
export WEB_PASS="sua_senha"
```

## InfluxDB local (auto)
O installer configura um InfluxDB local (v1) e cria o database `GarminStats`,
deixando o sync transparente para o usuario final.

## Troubleshooting rapido
- `OPENAI_API_KEY` ausente: o coach aborta com erro
- Influx sem dados: `sync_influx_to_sqlite.sh` loga "sem series"
- FIT nao gerado: verifique `node` e `npm install` em `/opt/ultra-coach/fit`
