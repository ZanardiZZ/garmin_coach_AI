import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import crypto from 'node:crypto';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

const PORT = Number(process.env.PORT || 8080);
const DB = process.env.ULTRA_COACH_DB || '/var/lib/ultra-coach/coach.sqlite';
const ATHLETE_DEFAULT = process.env.ATHLETE || 'zz';
const BASIC_USER = process.env.WEB_USER || '';
const BASIC_PASS = process.env.WEB_PASS || '';
const KEY_PATH =
  process.env.ULTRA_COACH_KEY_PATH ||
  path.join(os.homedir(), '.ultra-coach', 'secret.key');

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use('/public', express.static(path.join(__dirname, 'public')));
app.use(express.urlencoded({ extended: true }));

function runSql(sql) {
  return new Promise((resolve, reject) => {
    execFile(
      'sqlite3',
      ['-separator', '|', DB, sql],
      { maxBuffer: 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err) {
          return reject(new Error(stderr || err.message));
        }
        resolve(stdout.trim());
      }
    );
  });
}

function sqlEscape(value) {
  return String(value ?? '').replace(/'/g, "''");
}

function ensureKey() {
  if (fs.existsSync(KEY_PATH)) return;
  const dir = path.dirname(KEY_PATH);
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const key = crypto.randomBytes(32).toString('base64');
  fs.writeFileSync(KEY_PATH, `${key}\n`, { mode: 0o600 });
}

function readKey() {
  ensureKey();
  const raw = fs.readFileSync(KEY_PATH, 'utf8').trim();
  return Buffer.from(raw, 'base64');
}

function encryptValue(value, key) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(String(value ?? ''), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `v1:${iv.toString('base64')}:${tag.toString('base64')}:${enc.toString('base64')}`;
}

function decryptValue(enc, key) {
  const parts = String(enc || '').split(':');
  if (parts.length !== 4 || parts[0] !== 'v1') return '';
  const iv = Buffer.from(parts[1], 'base64');
  const tag = Buffer.from(parts[2], 'base64');
  const data = Buffer.from(parts[3], 'base64');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}

async function ensureConfigTable() {
  await runSql(
    `CREATE TABLE IF NOT EXISTS config_kv (
      key TEXT PRIMARY KEY,
      value_enc TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT
    );`
  );
}

async function loadConfigMap() {
  await ensureConfigTable();
  const key = readKey();
  const rows = await runSql('SELECT key, value_enc FROM config_kv;');
  const map = {};
  if (!rows) return map;
  for (const line of rows.split('\n')) {
    const [k, v] = line.split('|');
    if (!k || !v) continue;
    try {
      map[k] = decryptValue(v, key);
    } catch {
      map[k] = '';
    }
  }
  return map;
}

async function upsertConfig(map) {
  await ensureConfigTable();
  const key = readKey();
  const statements = [];
  for (const [k, v] of Object.entries(map)) {
    if (v === undefined) continue;
    const enc = encryptValue(v, key);
    const safeKey = sqlEscape(k);
    const safeVal = sqlEscape(enc);
    statements.push(
      `INSERT INTO config_kv (key, value_enc, created_at, updated_at)
       VALUES ('${safeKey}', '${safeVal}', datetime('now'), datetime('now'))
       ON CONFLICT(key) DO UPDATE SET value_enc=excluded.value_enc, updated_at=datetime('now');`
    );
  }
  if (!statements.length) return;
  await runSql(`BEGIN; ${statements.join(' ')} COMMIT;`);
}

async function upsertAthletes(athletes) {
  if (!athletes.length) return;
  const statements = [];
  for (const a of athletes) {
    const athleteId = sqlEscape(a.athlete_id);
    const name = sqlEscape(a.name);
    const goal = sqlEscape(a.goal_event || '');
    const coachMode = sqlEscape(a.coach_mode || 'moderate');
    const weeklyHours =
      a.weekly_hours === '' || a.weekly_hours === null || a.weekly_hours === undefined
        ? 'NULL'
        : Number(a.weekly_hours);
    statements.push(
      `INSERT INTO athlete_profile (athlete_id, name, hr_max, hr_rest, goal_event, weekly_hours_target, created_at, updated_at)
       VALUES ('${athleteId}', '${name}', ${Number(a.hr_max)}, ${Number(a.hr_rest)}, '${goal}', ${weeklyHours}, datetime('now'), datetime('now'))
       ON CONFLICT(athlete_id) DO UPDATE SET
         name=excluded.name,
         hr_max=excluded.hr_max,
         hr_rest=excluded.hr_rest,
         goal_event=excluded.goal_event,
         weekly_hours_target=excluded.weekly_hours_target,
         updated_at=datetime('now');`
    );
    statements.push(
      `INSERT INTO athlete_state (athlete_id, coach_mode, updated_at)
       VALUES ('${athleteId}', '${coachMode}', datetime('now'))
       ON CONFLICT(athlete_id) DO UPDATE SET coach_mode=excluded.coach_mode, updated_at=datetime('now');`
    );
  }
  await runSql(`BEGIN; ${statements.join(' ')} COMMIT;`);
}

function basicAuth(req, res, next) {
  if (!BASIC_USER || !BASIC_PASS) return next();
  const header = req.headers.authorization || '';
  const token = header.split(' ')[1] || '';
  const decoded = Buffer.from(token, 'base64').toString('utf8');
  const [user, pass] = decoded.split(':');
  if (user === BASIC_USER && pass === BASIC_PASS) return next();
  res.set('WWW-Authenticate', 'Basic realm="Ultra Coach"');
  res.status(401).send('Auth required');
}

app.use(basicAuth);

app.get('/setup', async (req, res) => {
  try {
    const config = await loadConfigMap();
    const rows = await runSql('SELECT athlete_id, name, hr_max, hr_rest, goal_event, weekly_hours_target, coach_mode FROM athlete_profile p LEFT JOIN athlete_state s ON s.athlete_id = p.athlete_id ORDER BY p.athlete_id;');
    const athletes = rows
      ? rows.split('\n').map((line) => {
          const [athlete_id, name, hr_max, hr_rest, goal_event, weekly_hours_target, coach_mode] =
            line.split('|');
          return {
            athlete_id,
            name,
            hr_max,
            hr_rest,
            goal_event,
            weekly_hours_target,
            coach_mode: coach_mode || 'moderate',
          };
        })
      : [];
    res.render('setup', { config, athletes });
  } catch (err) {
    res.status(500).send(`Erro no setup: ${err.message}`);
  }
});

app.post('/setup', async (req, res) => {
  try {
    const count = Number(req.body.athlete_count || 1);
    const athletes = [];
    for (let i = 0; i < count; i += 1) {
      const suffix = i + 1;
      const athlete_id = String(req.body[`athlete_id_${suffix}`] || '').trim();
      const name = String(req.body[`name_${suffix}`] || '').trim();
      const hr_max = String(req.body[`hr_max_${suffix}`] || '').trim();
      const hr_rest = String(req.body[`hr_rest_${suffix}`] || '50').trim();
      if (!athlete_id || !name || !hr_max) continue;
      athletes.push({
        athlete_id,
        name,
        hr_max,
        hr_rest,
        goal_event: String(req.body[`goal_${suffix}`] || '').trim(),
        weekly_hours: String(req.body[`weekly_hours_${suffix}`] || '').trim(),
        coach_mode: String(req.body[`coach_mode_${suffix}`] || 'moderate').trim(),
      });
    }

    await upsertConfig({
      OPENAI_API_KEY: req.body.openai_api_key || '',
      MODEL: req.body.model || 'gpt-5',
      INFLUX_URL: req.body.influx_url || '',
      INFLUX_DB: req.body.influx_db || '',
      INFLUX_USER: req.body.influx_user || '',
      INFLUX_PASS: req.body.influx_pass || '',
      TELEGRAM_BOT_TOKEN: req.body.telegram_token || '',
      TELEGRAM_CHAT_ID: req.body.telegram_chat_id || '',
      WEBHOOK_URL: req.body.webhook_url || '',
      GARMINCONNECT_EMAIL: req.body.garmin_email || '',
      GARMINCONNECT_PASSWORD: req.body.garmin_password || '',
      GARMINCONNECT_IS_CN: req.body.garmin_is_cn || 'false',
      GARMIN_TOKEN_DIR: req.body.garmin_token_dir || '',
      GARMIN_SYNC_DAYS: req.body.garmin_sync_days || '7',
      WEEKLY_SUMMARY_DAY: req.body.weekly_summary_day || '1',
      WEEKLY_SUMMARY_TIME: req.body.weekly_summary_time || '07:00',
      WEEKLY_SUMMARY_TZ: req.body.weekly_summary_tz || 'America/Sao_Paulo',
      ATHLETE: athletes.length === 1 ? athletes[0].athlete_id : ATHLETE_DEFAULT,
    });

    await upsertAthletes(athletes);
    res.redirect('/');
  } catch (err) {
    res.status(500).send(`Erro ao salvar setup: ${err.message}`);
  }
});

app.get('/', async (req, res) => {
  const athleteId = String(req.query.athlete || ATHLETE_DEFAULT);
  const safeAthlete = athleteId.replace(/'/g, "''");

  try {
    const profileRow = await runSql(
      `SELECT athlete_id, name, goal_event FROM athlete_profile WHERE athlete_id='${safeAthlete}' LIMIT 1;`
    );
    if (!profileRow) {
      return res.redirect('/setup');
    }
    const [athlete_id, name, goal_event] = profileRow.split('|');

    const stateRow = await runSql(
      `SELECT readiness_score, fatigue_score, coach_mode FROM athlete_state WHERE athlete_id='${safeAthlete}' LIMIT 1;`
    );
    const [readiness, fatigue, coach_mode] = (stateRow || '0|0|n/a').split('|');

    const weeklyRow = await runSql(
      `SELECT quality_days, long_days, total_time_min, total_load, total_distance_km
       FROM weekly_state
       WHERE athlete_id='${safeAthlete}'
         AND week_start=date('now','localtime','weekday 1','-7 days')
       LIMIT 1;`
    );
    const [q_days, l_days, w_time, w_load, w_dist] = (weeklyRow || '0|0|0|0|0').split('|');

    const lastRow = await runSql(
      `SELECT start_at, distance_km, duration_min, avg_hr, tags
       FROM session_log
       WHERE athlete_id='${safeAthlete}'
       ORDER BY start_at DESC
       LIMIT 1;`
    );
    const [last_at, last_dist, last_dur, last_hr, last_tags] = (lastRow || '||||').split('|');

    const todayRow = await runSql(
      `SELECT plan_date, workout_type, ai_status, duration_min, workout_title
       FROM v_today_plan
       WHERE athlete_id='${safeAthlete}'
       LIMIT 1;`
    );
    const [plan_date, workout_type, ai_status, duration_min, workout_title] =
      (todayRow || '||||').split('|');

    const complianceRow = await runSql(
      `SELECT COUNT(*),
              SUM(CASE WHEN status='accepted' THEN 1 ELSE 0 END),
              SUM(CASE WHEN status='rejected' THEN 1 ELSE 0 END)
       FROM daily_plan_ai
       WHERE athlete_id='${safeAthlete}'
         AND plan_date >= date('now','localtime','-30 days');`
    );
    const [plan_total, plan_ok, plan_rej] = (complianceRow || '0|0|0').split('|');

    const longRows = await runSql(
      `SELECT start_at, distance_km
       FROM session_log
       WHERE athlete_id='${safeAthlete}'
         AND tags LIKE '%long%'
       ORDER BY start_at DESC
       LIMIT 4;`
    );
    const longRuns = longRows
      ? longRows.split('\n').map((row) => {
          const [d, km] = row.split('|');
          return { date: d, km };
        })
      : [];

    res.render('index', {
      setupUrl: '/setup',
      athlete_id,
      name,
      goal_event,
      readiness: Number(readiness || 0),
      fatigue: Number(fatigue || 0),
      coach_mode,
      weekly: {
        q_days: Number(q_days || 0),
        l_days: Number(l_days || 0),
        time_min: Number(w_time || 0),
        load: Number(w_load || 0),
        dist_km: Number(w_dist || 0),
      },
      last: { last_at, last_dist, last_dur, last_hr, last_tags },
      today: { plan_date, workout_type, ai_status, duration_min, workout_title },
      compliance: {
        total: Number(plan_total || 0),
        ok: Number(plan_ok || 0),
        rej: Number(plan_rej || 0),
      },
      longRuns,
    });
  } catch (err) {
    res.status(500).send(`Erro ao carregar dados: ${err.message}`);
  }
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Ultra Coach Web rodando em http://localhost:${PORT}`);
});
