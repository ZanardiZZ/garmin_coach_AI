# garmin_coach_AI

Projeto para gerar treinos diários (ultra endurance) com:
- decisão determinística (regras + estado semanal)
- IA apenas para variação controlada (constraints)
- persistência em SQLite
- export opcional para FIT (workout) e envio via Telegram

## Estrutura
- `/opt/ultra-coach` (código)
- `/var/lib/ultra-coach` (dados: coach.sqlite, logs, exports)
- symlinks em `/usr/local/bin` apontando para `/opt/ultra-coach/bin`

## Rodar
```bash
/usr/local/bin/run_coach_daily.sh
