# Repository Guidelines

## Project Structure & Module Organization
- `bin/`: CLI scripts for sync, planning, setup, and automation (Bash/Python).
- `web/`: Express + EJS dashboard and setup wizard.
- `fit/`: FIT workout generator (Node.js) and tests.
- `sql/`: SQLite schema and migrations.
- `templates/`: Prompt templates and coach text assets.
- `tests/`: BATS/Vitest suites with fixtures and helpers.
- System data lives in `/var/lib/ultra-coach` and config in `/etc/ultra-coach/env`.

## Build, Test, and Development Commands
- `sudo ./install.sh`: one-shot installer (deps, DB, cron, web).
- `make test`: run full test suite (Bash + Node + SQL).
- `make lint`: run shellcheck + ESLint.
- `PORT=8080 /usr/bin/node web/app.js`: run the web dashboard locally.
- `/opt/ultra-coach/bin/run_coach_daily.sh`: run the daily pipeline manually.
- `/opt/ultra-coach/bin/init_db.sh --migrate`: apply pending migrations.
- `ATHLETE_ID=zz /opt/ultra-coach/bin/sync_influx_to_sqlite.sh`: sync Garmin/Influx into SQLite.
- `/opt/ultra-coach/bin/garmin_sync.sh`: Garmin Connect → InfluxDB (ActivityGPS when enabled).
- `http://<host>:8080/setup`: web wizard for config and athletes.

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
- Commits are short, imperative, and scoped to a single change (e.g., “Add weekly plan sender”).
- PRs should include a brief summary, key files touched, and test results.
- If UI changes are made, include screenshots or a short screen capture.

## Architecture Overview
- Pipeline: Garmin Connect → InfluxDB (local v1) → SQLite → daily coach run → FIT export → Telegram.
- Deterministic rules select workout type; OpenAI adds constrained variation.
- FIT export lives in `fit/` and uses Garmin FIT SDK.

## Security & Configuration Tips
- Secrets are stored encrypted in SQLite (`config_kv`) using a local key in `~/.ultra-coach/secret.key`.
- Avoid committing credentials or device tokens; use `/setup` or `/etc/ultra-coach/env`.
- Default paths: `/opt/ultra-coach` (code), `/var/lib/ultra-coach` (data), `/etc/ultra-coach` (env).
