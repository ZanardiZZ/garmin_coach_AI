# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ultra Coach is an AI-powered daily training generator for ultra endurance running (12h / ~90km events). The system uses a hybrid approach:
- **Deterministic planning**: Rule-based logic determines workout type (recovery, easy, quality, long) based on athlete state and weekly patterns
- **AI variation**: OpenAI API generates detailed workout structures within strict constraints
- **Data pipeline**: Garmin Connect (`bin/garmin_sync.py`) → InfluxDB (local v1) → SQLite → Daily coach run → FIT export → Telegram notification
- **Coach chat**: Web/Telegram → `coach_chat` + `athlete_feedback` → usado nas constraints do dia seguinte
- **Grafana**: Dashboards prontos do garmin-grafana embutidos no web

## Directory Structure

```
/opt/ultra-coach/          # Project code (this repo)
  bin/                     # Shell scripts
  fit/                     # FIT file converter (Node.js)
  sql/                     # Database schema and migrations
  templates/               # AI prompt templates
/var/lib/ultra-coach/      # Data directory
  coach.sqlite             # Main database
  logs/                    # Log files
  exports/                 # Generated FIT files
  backups/                 # Database backups
/etc/ultra-coach/          # System configuration
  env                      # Environment variables (NOT versioned)
```

## Common Commands

### Daily Coach Run
```bash
# Normal run (generates workout, sends to Telegram)
/usr/local/bin/run_coach_daily.sh

# Dry run (shows what would be sent without calling OpenAI)
/usr/local/bin/run_coach_daily.sh --dry-run

# Verbose mode
/usr/local/bin/run_coach_daily.sh --verbose
```

### Database Management
```bash
# Initialize database (first time or with --reset)
/usr/local/bin/init_db.sh

# Apply pending migrations only
/usr/local/bin/init_db.sh --migrate

# Check migration status
/usr/local/bin/init_db.sh --check

# Reset database (WARNING: deletes all data)
/usr/local/bin/init_db.sh --reset

# Create backup
/usr/local/bin/backup_db.sh

# Compressed backup, keep last 30
/usr/local/bin/backup_db.sh --compress --keep 30
```

### Data Sync
```bash
# Sync from InfluxDB to SQLite
ATHLETE_ID=zz /opt/ultra-coach/bin/sync_influx_to_sqlite.sh

# Garmin Connect -> InfluxDB (includes ActivityGPS when enabled)
/opt/ultra-coach/bin/garmin_sync.sh

# Telegram coach bot (chat/feedback)
/usr/local/bin/telegram_coach_bot.sh
```

### FIT File Generation
```bash
# Generate FIT workout file from JSON
node /opt/ultra-coach/fit/workout_to_fit.mjs \
  --in workout.json \
  --out workout.fit \
  --constraints constraints.json
```

### Installation
```bash
# Standard installation (requires root)
sudo ./install.sh

# Upgrade sem perder dados
sudo ./install.sh --upgrade

# Skip symlinks or FIT dependencies
sudo ./install.sh --no-symlinks --no-fit-deps

# One-line installer (recommended)
curl -fsSL https://raw.githubusercontent.com/ZanardiZZ/garmin_coach_AI/main/install.sh | sudo bash
```

## Commit Conventions (Release-Please)

- Use Conventional Commits (e.g., `feat: ...`, `fix: ...`, `chore: ...`).
- Breaking changes must use `!` and/or a `BREAKING CHANGE:` footer.
- Release-Please generates version bumps and changelog from commit history.
- Evite breaking changes; apos 1.0 a expectativa e nao ter breaking.

## Architecture

### Daily Pipeline Flow

1. **Sync** (`sync_influx_to_sqlite.sh`): Imports last N days of Garmin data from InfluxDB
   - Running activities → `session_log` table
   - Body composition (Index S2) → `body_comp_log` table
   - Auto-tags activities: `long` (≥18km or ≥110min), `quality` (≥10min in Z3+), `easy`

2. **State Calculation** (`run_coach_daily.sh` SQL blocks):
   - `athlete_state`: Computes readiness, fatigue, monotony, strain from last 7/28 days
   - `weekly_state`: Tracks quality_days, long_days, total_time/load for current week

3. **Deterministic Planning** (`daily_plan` table):
   - Rule-based decision tree determines workout type:
     - Recovery if readiness < floor or fatigue > cap
     - Long on weekends if weekly budget allows
     - Quality on Tue/Thu if weekly budget allows
     - Easy otherwise

4. **Constraint Generation** (`daily_plan_ai` table):
   - Creates `constraints_json` with:
     - `allowed_type`: locked workout type
     - Duration ranges (`duration_min`, `duration_max`)
     - `hard_minutes_cap`: max minutes in Z3+ (0 for easy/recovery)
     - HR caps (`z2_hr_cap`, `z3_hr_floor`)
     - Weekly budget info for context
     - Long run metadata (`back_to_back_day`, `long_role`: main/secondary)

5. **AI Generation**:
   - Calls OpenAI Responses API with `templates/coach_prompt_ultra.txt`
   - Validates response against constraints
   - Rejects if type mismatch, duration violation, or forbidden intensities when `hard_cap=0`
   - Saves accepted JSON to `daily_plan_ai.ai_workout_json`

6. **FIT Export** (optional):
   - Converts workout JSON → Garmin FIT format via `workout_to_fit.mjs`
   - Sends as Telegram document if `TELEGRAM_BOT_TOKEN` configured

7. **Notification**:
   - Weekly summary via `send_weekly_plan.sh` (Telegram bot)
   - Daily workout via Telegram bot (webhook only if custom integration is added)

### Database Schema

**Core Tables:**
- `athlete_profile`: Physiological data (hr_max, hr_rest, goal_event)
- `athlete_state`: Current readiness/fatigue (recalculated daily)
- `weekly_state`: Weekly volume tracking (triggers on `session_log` insert)
- `session_log`: Training history (imported from Garmin/InfluxDB)
- `body_comp_log`: Body composition from Index S2 scale
- `coach_chat`: Conversas (web/telegram)
- `athlete_feedback`: Feedback subjetivo do treino
- `coach_policy`: Training policies by mode (conservative/moderate/aggressive)
- `daily_plan`: Deterministic workout type decision
- `daily_plan_ai`: AI-generated workout structure with constraints

**Key Relationships:**
- `athlete_state.coach_mode` → `coach_policy.mode` (determines readiness_floor, fatigue_cap, max_hard_days_week)
- `daily_plan.workout_type` → `daily_plan_ai.allowed_type` (constraint for AI)
- Trigger `trg_session_log_update_weekly` auto-updates `weekly_state` on new activities

### Constraint Validation Logic

**When `hard_minutes_cap=0` (recovery/easy days):**
- Run 3 validation passes (all must pass):
  1. Regex scan for forbidden keywords: `z3|z4|tiro|threshold|limiar|vo2|maximal|all-out`
  2. Check segment `intensity` fields for: `z3|z4|forte|duro|intenso|limiar|vo2`
  3. Detect repetition patterns: `[0-9]{1,2}[xX][0-9]{2,4}` (e.g., "10x1000")
- Allows: Z1, Z2, progressive (capped at `z2_hr_cap`), run/walk, intervals only if rest/walk

**When `hard_minutes_cap>0` (quality/long days):**
- No keyword blocking
- AI must stay within cap for hard efforts

### Configuration

Environment variables are in `/etc/ultra-coach/env` (created by `install.sh`, NOT versioned):
```bash
# Paths
ULTRA_COACH_PROJECT_DIR=/opt/ultra-coach
ULTRA_COACH_DATA_DIR=/var/lib/ultra-coach
ULTRA_COACH_DB=/var/lib/ultra-coach/coach.sqlite
ULTRA_COACH_PROMPT_FILE=/opt/ultra-coach/templates/coach_prompt_ultra.txt
ULTRA_COACH_FIT_DIR=/opt/ultra-coach/fit

# Athlete ID
ATHLETE=zz

# OpenAI
OPENAI_API_KEY=sk-...
MODEL=gpt-5  # or gpt-4o, etc.

# InfluxDB (Garmin data source)
INFLUX_URL=http://localhost:8086/query
INFLUX_DB=GarminStats
INFLUX_USER=  # if v1.x auth enabled
INFLUX_PASS=

# Telegram (for FIT document attachment)
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# Garmin Connect
GARMINCONNECT_EMAIL=
GARMINCONNECT_PASSWORD=
GARMIN_SYNC_DAYS=30
GARMIN_FETCH_ACTIVITY_DETAILS=true
```

## Web Setup & Dashboard

- Wizard: `http://<host>:8080/setup` (stores secrets encrypted in SQLite `config_kv`).
- Dashboard: `http://<host>:8080/` for status + weekly view.
- Activities: `http://<host>:8080/activities` and `/activity/:id` for maps and charts.
- Coach: `http://<host>:8080/coach` (chat e feedback)
- Grafana: `http://<host>:8080/grafana`

## Versioning & Changelog

- Current version lives in `VERSION`; changelog in `CHANGELOG.md`.
- Use `bin/release.sh patch|minor|major` to bump, update changelog, and sync package versions.
- Optional tag: `bin/release.sh 0.2.1 --tag`.

## Key Design Principles

1. **Idempotency**: All scripts can be re-run safely. Database inserts use `INSERT OR REPLACE` / `ON CONFLICT` / `WHERE NOT EXISTS`.

2. **Separation of Concerns**:
   - Shell scripts handle orchestration, data sync, validation
   - SQL handles state calculation and aggregation
   - AI handles creative variation within constraints
   - Node.js handles FIT binary encoding

3. **Safety First**:
   - Backups before critical operations (`backup_db.sh` auto-called by daily run)
   - Strict validation of AI output (type, duration, intensity)
   - Rejection tracking with `rejection_reason` field
   - Retry logic with exponential backoff for OpenAI calls (3 attempts)

4. **Ultra-Specific Logic**:
   - Back-to-back long runs (Sat main + Sun secondary)
   - Run/walk strategies for sustainability
   - Nutrition/hydration planning (carbs_g_per_h, fluids_ml_per_h, sodium_mg_per_h)
   - Progressive overload via weekly budgets (max_quality_week, max_long_week)

5. **TRIMP-Based Load Management**:
   - Uses Banister TRIMP formula: `duration_min * HRR * 0.64 * exp(1.92 * HRR)`
   - HRR (Heart Rate Reserve) = `(avg_hr - hr_rest) / (hr_max - hr_rest)`
   - Computed in `sync_influx_to_sqlite.sh:calc_trimp()`

## Development Notes

- **Language**: Bash (scripts), SQL (schema/queries), JavaScript/Node.js (FIT converter)
- **Node.js version**: Requires Node ≥18 for ES modules in FIT converter
- **Dependencies**: `sqlite3`, `curl`, `jq`, `node`, `npm`, `python3` (venv for Garmin sync)
- **FIT SDK**: Uses `@garmin/fitsdk` v21.180.0 for workout file generation
- **AI Prompt**: Stored in `templates/coach_prompt_ultra.txt` (Portuguese, ultra-focused, structured JSON schema)
- **Logging**: Structured format `[ISO8601][component][level] message`
- **Security**: Uses `sql_escape()` in sync script to prevent SQL injection; single quotes doubled

## Modifying the System

**To add a new constraint:**
1. Update SQL in `run_coach_daily.sh` that generates `constraints_json`
2. Document in `templates/coach_prompt_ultra.txt` if AI needs to understand it
3. Add validation in validation block (lines ~465-498 of `run_coach_daily.sh`)

**To change workout selection rules:**
- Edit the `decision` CTE in `run_coach_daily.sh` (lines ~255-279)

**To add database fields:**
1. Add column to `sql/schema.sql`
2. Create migration in `sql/migrations/NNN_description.sql`
3. Run `init_db.sh --migrate`

**To test without OpenAI costs:**
```bash
run_coach_daily.sh --dry-run  # Shows constraints, skips API call
```

**To debug constraint validation:**
```bash
# Check logs for rejection reasons
sqlite3 /var/lib/ultra-coach/coach.sqlite \
  "SELECT plan_date, status, rejection_reason FROM daily_plan_ai WHERE athlete_id='zz' ORDER BY plan_date DESC LIMIT 10;"
```

## Testing

### Running Tests

The project has a comprehensive test suite covering Bash scripts, Node.js code, and SQL logic.

```bash
# Install test dependencies (first time only)
./tests/install_deps.sh

# Install git hooks (recommended)
./tests/install_hooks.sh

# Run all tests
make test

# Run specific test suites
make test-unit        # Unit tests only (Bash + Node.js)
make test-unit-bash   # Bash unit tests
make test-node        # All Node.js tests
make test-sql         # SQL tests (schema, triggers)

# Generate coverage report
make coverage

# Run linting
make lint
```

### Test Structure

```
tests/
├── unit/bash/         # Bash unit tests (BATS)
│   ├── calc_trimp.bats
│   ├── retry_curl.bats
│   ├── sql_escape.bats
│   └── validation.bats
├── unit/node/         # Node.js unit tests (Vitest)
│   ├── input_validation.test.mjs
│   ├── hr_target_logic.test.mjs
│   └── workout_to_fit.test.mjs
├── sql/               # SQL integrity tests
│   ├── schema_integrity.bats
│   └── triggers.bats
├── helpers/           # Test utilities
├── fixtures/          # Test data (DBs, JSONs, OpenAI responses)
└── README.md          # Detailed testing guide
```

### Coverage Thresholds

- **Bash critical functions**: 100% (calc_trimp, retry_curl, sql_escape, validation)
- **Node.js (workout_to_fit)**: 80%
- **SQL (triggers, migrations)**: 100%

### CI/CD

**GitHub Actions** (`.github/workflows/test.yml`):
- Runs automatically on push/PR to `main` or `develop`
- Tests across Node.js 18/20/22
- Uploads coverage to Codecov
- Runs shellcheck and ESLint

**Git Hooks**:
- `pre-commit`: Runs unit tests before commit
- `pre-push`: Runs full test suite before push
- Bypass with `--no-verify` if needed

### Writing Tests

See `tests/README.md` for detailed guide including:
- How to write BATS tests
- How to write Vitest tests
- Using fixtures and mocks
- Debugging failed tests
- Test helpers and assertions

### Testing Requirements for PRs

All pull requests must:
1. ✅ Pass all tests (`make test`)
2. ✅ Meet coverage thresholds (`make coverage`)
3. ✅ Pass linting (`make lint`)
4. ✅ Have git hooks installed (`./tests/install_hooks.sh`)
