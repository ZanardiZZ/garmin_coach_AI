# Repository Guidelines

## Project Structure & Module Organization
- `bin/`: CLI scripts for sync, planning, setup, and automation (Bash/Python).
- `web/`: Express + EJS dashboard and setup wizard.
- `fit/`: FIT workout generator (Node.js) and tests.
- `sql/`: SQLite schema and migrations.
- `templates/`: Prompt templates and coach text assets.
- `tests/`: BATS/Vitest suites with fixtures.
- System data lives in `/var/lib/ultra-coach` and config in `/etc/ultra-coach/env`.

## Build, Test, and Development Commands
- `sudo ./install.sh`: one-shot installer (deps, DB, cron, web).
- `sudo ./install.sh --upgrade`: atualiza repo e migrations sem resetar dados.
- `/opt/ultra-coach/bin/uninstall.sh`: remove cron, symlinks, e para serviços (sem apagar dados).
- `make test`: run full test suite (Bash + Node + SQL).
- `make test-e2e-ui`: smoke test UI do dashboard (Playwright).
- `make lint`: run shellcheck + ESLint.
- `PORT=8080 /usr/bin/node web/app.js`: run the web dashboard locally.
- `/opt/ultra-coach/bin/run_coach_daily.sh`: run the daily pipeline manually.
- `/opt/ultra-coach/bin/init_db.sh --migrate`: apply pending migrations.
- `ATHLETE_ID=zz /opt/ultra-coach/bin/sync_influx_to_sqlite.sh`: sync Garmin/Influx into SQLite.
- `/opt/ultra-coach/bin/garmin_sync.sh`: Garmin Connect → InfluxDB (ActivityGPS when enabled).
- `http://<host>:8080/setup`: web wizard for config and athletes.
- `bin/release.sh patch`: bumps `VERSION`, updates `CHANGELOG.md`, and syncs package versions.
- `/opt/ultra-coach/bin/telegram_coach_bot.sh`: bot de chat/feedback (Telegram).
- `http://<host>:8080/grafana`: dashboards Grafana embutidos.

## Coding Style & Naming Conventions
- Bash: use `set -euo pipefail`, prefer `#!/usr/bin/env bash`, and run `shellcheck`.
- Node/JS: ES modules, 2-space indentation, and lint with ESLint.
- SQL: keep migrations in `sql/migrations/` and schema updates in `sql/schema.sql`.
- Filenames: snake_case for scripts, kebab-case for web assets, and `.ejs` for views.

## Testing Guidelines
- Bash tests use BATS; Node tests use Vitest (in `fit/`).
- Follow existing naming like `tests/unit/bash/*.bats` and `tests/unit/node/*.test.mjs`.
- Run targeted tests, e.g. `bats tests/unit/bash/calc_trimp.bats` or `cd fit && npm test`.
- Coverage targets: Bash critical functions and SQL at 100%; Node FIT generator at 80%.
- Git hooks: `./tests/install_hooks.sh` installs pre-commit and pre-push checks.

## Commit & Pull Request Guidelines
- Commits follow Conventional Commits (e.g., `feat: add weekly plan sender`, `fix: handle NaN pace`).
- Use `feat!:` or `fix!:` for breaking changes and include `BREAKING CHANGE:` in the body.
- Breaking changes devem ser raras; a meta e evitar breaking apos a versao 1.0.
- PRs should include a brief summary, key files touched, and test results.
- If UI changes are made, include screenshots or a short screen capture.

## Architecture Overview
- Pipeline: Garmin Connect → InfluxDB (local v1) → SQLite → daily coach run → FIT export → Telegram.
- Deterministic rules select workout type; OpenAI adds constrained variation.
- FIT export lives in `fit/` and uses Garmin FIT SDK.
 - Coach chat (web/Telegram) grava memoria em `coach_chat` e feedback em `athlete_feedback`.
 - Grafana roda local e usa dashboards provisionados do projeto garmin-grafana.

## Security & Configuration Tips
- Secrets are stored encrypted in SQLite (`config_kv`) using a local key in `~/.ultra-coach/secret.key`.
- Avoid committing credentials or device tokens; use `/setup` or `/etc/ultra-coach/env`.
- Default paths: `/opt/ultra-coach` (code), `/var/lib/ultra-coach` (data), `/etc/ultra-coach` (env).
