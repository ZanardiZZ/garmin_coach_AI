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

async function insertCoachChat(athleteId, channel, role, message) {
  const safeAthlete = sqlEscape(athleteId);
  const safeChannel = sqlEscape(channel);
  const safeRole = sqlEscape(role);
  const safeMessage = sqlEscape(message);
  await runSql(
    `INSERT INTO coach_chat (athlete_id, channel, role, message, created_at)
     VALUES ('${safeAthlete}', '${safeChannel}', '${safeRole}', '${safeMessage}', datetime('now'));`
  );
}

async function getCoachChatHistory(athleteId, limit = 20) {
  const safeAthlete = sqlEscape(athleteId);
  const rows = await runSql(
    `SELECT role, message, created_at
     FROM coach_chat
     WHERE athlete_id='${safeAthlete}'
     ORDER BY created_at DESC
     LIMIT ${Number(limit)};`
  );
  if (!rows) return [];
  return rows
    .split('\n')
    .map((line) => {
      const [role, message, created_at] = line.split('|');
      return { role, message, created_at };
    })
    .reverse();
}

async function insertFeedback(athleteId, data) {
  const safeAthlete = sqlEscape(athleteId);
  const sessionDate = data.session_date ? `'${sqlEscape(data.session_date)}'` : 'NULL';
  const perceived = data.perceived ? `'${sqlEscape(data.perceived)}'` : 'NULL';
  const rpeValue = toNumberOrNull(data.rpe);
  const rpe = rpeValue === null ? 'NULL' : rpeValue;
  const conditions = data.conditions ? `'${sqlEscape(data.conditions)}'` : 'NULL';
  const notes = data.notes ? `'${sqlEscape(data.notes)}'` : 'NULL';
  await runSql(
    `INSERT INTO athlete_feedback (athlete_id, session_date, perceived, rpe, conditions, notes, created_at)
     VALUES ('${safeAthlete}', ${sessionDate}, ${perceived}, ${rpe}, ${conditions}, ${notes}, datetime('now'));`
  );
}

async function reschedulePlan(athleteId, fromDate, toDate) {
  const safeAthlete = sqlEscape(athleteId);
  const safeFrom = sqlEscape(fromDate);
  const safeTo = sqlEscape(toDate);
  const existingFrom = await runSql(
    `SELECT COUNT(*) FROM daily_plan WHERE athlete_id='${safeAthlete}' AND plan_date='${safeFrom}';`
  );
  if (!existingFrom || Number(existingFrom) === 0) {
    throw new Error('Plano de origem nao encontrado.');
  }
  const existingTo = await runSql(
    `SELECT COUNT(*) FROM daily_plan WHERE athlete_id='${safeAthlete}' AND plan_date='${safeTo}';`
  );
  const hasTarget = existingTo && Number(existingTo) > 0;

  if (hasTarget) {
    await runSql(
      `BEGIN;
       UPDATE daily_plan SET plan_date='${safeTo}' WHERE athlete_id='${safeAthlete}' AND plan_date='${safeFrom}';
       UPDATE daily_plan SET plan_date='${safeFrom}' WHERE athlete_id='${safeAthlete}' AND plan_date='${safeTo}' AND rowid != (SELECT rowid FROM daily_plan WHERE athlete_id='${safeAthlete}' AND plan_date='${safeFrom}' LIMIT 1);
       UPDATE daily_plan_ai SET plan_date='${safeTo}' WHERE athlete_id='${safeAthlete}' AND plan_date='${safeFrom}';
       UPDATE daily_plan_ai SET plan_date='${safeFrom}' WHERE athlete_id='${safeAthlete}' AND plan_date='${safeTo}' AND rowid != (SELECT rowid FROM daily_plan_ai WHERE athlete_id='${safeAthlete}' AND plan_date='${safeFrom}' LIMIT 1);
       COMMIT;`
    );
  } else {
    await runSql(
      `BEGIN;
       UPDATE daily_plan SET plan_date='${safeTo}', updated_at=datetime('now') WHERE athlete_id='${safeAthlete}' AND plan_date='${safeFrom}';
       UPDATE daily_plan_ai SET plan_date='${safeTo}', updated_at=datetime('now') WHERE athlete_id='${safeAthlete}' AND plan_date='${safeFrom}';
       COMMIT;`
    );
  }
}

async function getRecentFeedback(athleteId, days = 7, limit = 10) {
  const safeAthlete = sqlEscape(athleteId);
  const rows = await runSql(
    `SELECT COALESCE(session_date, date(created_at)), perceived, rpe, conditions, notes
     FROM athlete_feedback
     WHERE athlete_id='${safeAthlete}'
       AND date(created_at) >= date('now','localtime','-${Number(days)} days')
     ORDER BY created_at DESC
     LIMIT ${Number(limit)};`
  );
  if (!rows) return [];
  return rows.split('\n').map((line) => {
    const [date, perceived, rpe, conditions, notes] = line.split('|');
    return { date, perceived, rpe, conditions, notes };
  });
}

async function getRecentSessions(athleteId, limit = 5) {
  const safeAthlete = sqlEscape(athleteId);
  const rows = await runSql(
    `SELECT start_at, distance_km, duration_min, avg_hr, tags
     FROM session_log
     WHERE athlete_id='${safeAthlete}'
     ORDER BY start_at DESC
     LIMIT ${Number(limit)};`
  );
  if (!rows) return [];
  return rows.split('\n').map((line) => {
    const [start_at, distance_km, duration_min, avg_hr, tags] = line.split('|');
    return { start_at, distance_km, duration_min, avg_hr, tags };
  });
}

function buildCoachContext(feedback, sessions) {
  const feedbackLines = feedback.map((f) => {
    return `${f.date} ${f.perceived || ''} rpe=${f.rpe || ''} ${f.conditions || ''} ${f.notes || ''}`.trim();
  });
  const sessionLines = sessions.map((s) => {
    return `${s.start_at} ${Number(s.distance_km || 0).toFixed(1)}km ${Math.round(Number(s.duration_min || 0))}min HR ${Math.round(Number(s.avg_hr || 0))} ${s.tags || ''}`.trim();
  });
  return [
    'Feedback recente:',
    feedbackLines.length ? feedbackLines.join(' | ') : 'Sem feedback recente.',
    'Ultimas atividades:',
    sessionLines.length ? sessionLines.join(' | ') : 'Sem atividades recentes.',
  ].join('\n');
}

async function callCoach(model, apiKey, messages) {
  const body = {
    model,
    input: messages,
  };
  const res = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `OpenAI error ${res.status}`);
  }
  const payload = await res.json();
  const output = payload.output?.[0]?.content?.[0]?.text || '';
  return String(output).trim();
}
async function upsertAthletes(athletes) {
  if (!athletes.length) return;
  const statements = [];
  for (const a of athletes) {
    const athleteId = sqlEscape(a.athlete_id);
    const name = sqlEscape(a.name);
    const weight = toNumberOrNull(a.weight_kg);
    const ltHr = toNumberOrNull(a.lt_hr);
    const ltPace = toNumberOrNull(a.lt_pace_min_km);
    const ltPower = toNumberOrNull(a.lt_power_w);
    const goal = sqlEscape(a.goal_event || '');
    const coachMode = sqlEscape(a.coach_mode || 'moderate');
    const weeklyHoursValue = toNumberOrNull(a.weekly_hours);
    const weeklyHours = weeklyHoursValue === null ? 'NULL' : weeklyHoursValue;
    statements.push(
      `INSERT INTO athlete_profile (athlete_id, name, hr_max, hr_rest, weight_kg, lt_hr, lt_pace_min_km, lt_power_w, goal_event, weekly_hours_target, created_at, updated_at)
       VALUES ('${athleteId}', '${name}', ${Number(a.hr_max)}, ${Number(a.hr_rest)}, ${weight ?? 'NULL'}, ${ltHr ?? 'NULL'}, ${ltPace ?? 'NULL'}, ${ltPower ?? 'NULL'}, '${goal}', ${weeklyHours}, datetime('now'), datetime('now'))
       ON CONFLICT(athlete_id) DO UPDATE SET
         name=excluded.name,
         hr_max=excluded.hr_max,
         hr_rest=excluded.hr_rest,
         weight_kg=excluded.weight_kg,
         lt_hr=excluded.lt_hr,
         lt_pace_min_km=excluded.lt_pace_min_km,
         lt_power_w=excluded.lt_power_w,
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

function slugify(value) {
  const ascii = String(value ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^\x00-\x7F]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return ascii || 'athlete';
}

function parsePaceToMin(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  const cleaned = raw.replace(/[^0-9:.,]/g, '');
  if (!cleaned) return null;
  if (cleaned.includes(':')) {
    const [minStr, secStr] = cleaned.split(':');
    const mins = Number(minStr);
    const secs = Number(secStr);
    if (!Number.isFinite(mins) || !Number.isFinite(secs) || secs < 0 || secs >= 60) return null;
    return mins + secs / 60;
  }
  const normalized = cleaned.replace(',', '.');
  const asFloat = Number(normalized);
  return Number.isFinite(asFloat) ? asFloat : null;
}

function toNumberOrNull(value) {
  const num = Number(String(value ?? '').replace(',', '.'));
  return Number.isFinite(num) ? num : null;
}

function formatPaceMin(value) {
  const minutes = Number(value);
  if (!Number.isFinite(minutes) || minutes <= 0) return '';
  const mins = Math.floor(minutes);
  const secs = Math.round((minutes - mins) * 60);
  const adjMins = secs === 60 ? mins + 1 : mins;
  const adjSecs = secs === 60 ? 0 : secs;
  return `${adjMins}:${String(adjSecs).padStart(2, '0')}`;
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

async function getAthleteProfile(athleteId) {
  const safeAthlete = sqlEscape(athleteId);
  const row = await runSql(
    `SELECT athlete_id, name, hr_max, hr_rest, weight_kg, lt_hr, lt_pace_min_km, lt_power_w, goal_event
     FROM athlete_profile WHERE athlete_id='${safeAthlete}' LIMIT 1;`
  );
  if (!row) return null;
  const [athlete_id, name, hr_max, hr_rest, weight_kg, lt_hr, lt_pace_min_km, lt_power_w, goal_event] =
    row.split('|');
  return {
    athlete_id,
    name,
    hr_max: Number(hr_max || 0),
    hr_rest: Number(hr_rest || 0),
    weight_kg: weight_kg ? Number(weight_kg) : null,
    lt_hr: lt_hr ? Number(lt_hr) : null,
    lt_pace_min_km: lt_pace_min_km ? Number(lt_pace_min_km) : null,
    lt_power_w: lt_power_w ? Number(lt_power_w) : null,
    goal_event,
  };
}

async function getLatestWeight(athleteId) {
  const safeAthlete = sqlEscape(athleteId);
  const row = await runSql(
    `SELECT weight_kg FROM body_comp_log WHERE athlete_id='${safeAthlete}' ORDER BY measured_at DESC LIMIT 1;`
  );
  if (!row) return null;
  const value = Number(row.split('|')[0]);
  return Number.isFinite(value) ? value : null;
}

app.get('/setup', async (req, res) => {
  try {
    const config = await loadConfigMap();
    const rows = await runSql(
      'SELECT p.athlete_id, p.name, p.hr_max, p.hr_rest, p.weight_kg, p.lt_hr, p.lt_pace_min_km, p.lt_power_w, ' +
        'p.goal_event, p.weekly_hours_target, s.coach_mode ' +
        'FROM athlete_profile p LEFT JOIN athlete_state s ON s.athlete_id = p.athlete_id ORDER BY p.athlete_id;'
    );
    const athletes = rows
      ? rows.split('\n').map((line) => {
          const [
            athlete_id,
            name,
            hr_max,
            hr_rest,
            weight_kg,
            lt_hr,
            lt_pace_min_km,
            lt_power_w,
            goal_event,
            weekly_hours_target,
            coach_mode,
          ] = line.split('|');
          return {
            athlete_id,
            name,
            hr_max,
            hr_rest,
            weight_kg,
            lt_hr,
            lt_pace_min_km,
            lt_pace_display: formatPaceMin(lt_pace_min_km),
            lt_power_w,
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
    const existingIdsRows = await runSql('SELECT athlete_id FROM athlete_profile;');
    const usedIds = new Set(
      existingIdsRows ? existingIdsRows.split('\n').map((row) => row.split('|')[0]) : []
    );
    const athletes = [];
    for (let i = 0; i < count; i += 1) {
      const suffix = i + 1;
      const athlete_id = String(req.body[`athlete_id_${suffix}`] || '').trim();
      const name = String(req.body[`name_${suffix}`] || '').trim();
      const hr_max = String(req.body[`hr_max_${suffix}`] || '').trim();
      const hr_rest = String(req.body[`hr_rest_${suffix}`] || '50').trim();
      if (!name || !hr_max) continue;

      let finalId = athlete_id;
      if (!finalId) {
        const base = slugify(name);
        let candidate = base;
        let idx = 2;
        while (usedIds.has(candidate)) {
          candidate = `${base}_${idx}`;
          idx += 1;
        }
        finalId = candidate;
      }
      usedIds.add(finalId);

      athletes.push({
        athlete_id: finalId,
        name,
        hr_max,
        hr_rest,
        weight_kg: String(req.body[`weight_kg_${suffix}`] || '').trim(),
        lt_pace_min_km: parsePaceToMin(req.body[`lt_pace_${suffix}`]),
        lt_hr: String(req.body[`lt_hr_${suffix}`] || '').trim(),
        lt_power_w: String(req.body[`lt_power_${suffix}`] || '').trim(),
        goal_event: String(req.body[`goal_${suffix}`] || '').trim(),
        weekly_hours: String(req.body[`weekly_hours_${suffix}`] || '').trim(),
        coach_mode: String(req.body[`coach_mode_${suffix}`] || 'moderate').trim(),
      });
    }

    await upsertConfig({
      OPENAI_API_KEY: req.body.openai_api_key || '',
      MODEL: req.body.model || 'gpt-5',
      INFLUX_URL: 'http://localhost:8086/query',
      INFLUX_DB: 'GarminStats',
      INFLUX_USER: '',
      INFLUX_PASS: '',
      TELEGRAM_BOT_TOKEN: req.body.telegram_token || '',
      TELEGRAM_CHAT_ID: req.body.telegram_chat_id || '',
      WEBHOOK_URL: '',
      GARMINCONNECT_EMAIL: req.body.garmin_email || '',
      GARMINCONNECT_PASSWORD: req.body.garmin_password || '',
      GARMINCONNECT_IS_CN: req.body.garmin_is_cn || 'false',
      GARMIN_TOKEN_DIR: req.body.garmin_token_dir || '',
      GARMIN_SYNC_DAYS: req.body.garmin_sync_days || '7',
      GARMIN_FETCH_ACTIVITY_DETAILS: req.body.garmin_fetch_activity_details || 'true',
      WEEKLY_SUMMARY_DAY: req.body.weekly_summary_day || '1',
      WEEKLY_SUMMARY_TIME: req.body.weekly_summary_time || '07:00',
      WEEKLY_SUMMARY_TZ: req.body.weekly_summary_tz || 'America/Sao_Paulo',
      USER_TZ: req.body.weekly_summary_tz || 'America/Sao_Paulo',
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
      coachUrl: '/coach',
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

app.get('/activities', async (req, res) => {
  const athleteId = String(req.query.athlete || ATHLETE_DEFAULT);
  try {
    const profile = await getAthleteProfile(athleteId);
    if (!profile) return res.redirect('/setup');

    const rows = await runSql(
      `SELECT activity_id, start_at, distance_km, duration_min, avg_hr, tags
       FROM session_log
       WHERE athlete_id='${sqlEscape(athleteId)}'
         AND activity_id IS NOT NULL
       ORDER BY start_at DESC
       LIMIT 200;`
    );
    const activities = rows
      ? rows.split('\n').map((line) => {
          const [activity_id, start_at, distance_km, duration_min, avg_hr, tags] = line.split('|');
          return {
            activity_id,
            start_at,
            distance_km,
            duration_min,
            avg_hr,
            tags,
          };
        })
      : [];
    res.render('activities', { profile, activities });
  } catch (err) {
    res.status(500).send(`Erro ao carregar atividades: ${err.message}`);
  }
});

app.get('/coach', async (req, res) => {
  const athleteId = String(req.query.athlete || ATHLETE_DEFAULT);
  try {
    const profile = await getAthleteProfile(athleteId);
    if (!profile) return res.redirect('/setup');
    const history = await getCoachChatHistory(athleteId, 20);
    const feedback = await getRecentFeedback(athleteId, 14, 10);
    res.render('coach', { profile, history, feedback, error: req.query.error || '' });
  } catch (err) {
    res.status(500).send(`Erro ao carregar coach: ${err.message}`);
  }
});

app.post('/coach/send', async (req, res) => {
  const athleteId = String(req.body.athlete || ATHLETE_DEFAULT);
  const message = String(req.body.message || '').trim();
  if (!message) return res.redirect('/coach');
  try {
    const config = await loadConfigMap();
    const apiKey = config.OPENAI_API_KEY || '';
    const model = config.MODEL || 'gpt-5';
    if (!apiKey) return res.redirect('/coach?error=OPENAI_API_KEY ausente');

    await insertCoachChat(athleteId, 'web', 'user', message);

    const history = await getCoachChatHistory(athleteId, 12);
    const feedback = await getRecentFeedback(athleteId, 14, 10);
    const sessions = await getRecentSessions(athleteId, 5);
    const context = buildCoachContext(feedback, sessions);
    const messages = [
      {
        role: 'system',
        content:
          'Voce e um treinador de corrida focado em ultra endurance. Responda em PT-BR de forma pratica e objetiva.',
      },
      ...history.map((h) => ({ role: h.role, content: h.message })),
      { role: 'user', content: `Contexto:\\n${context}\\n\\nMensagem: ${message}` },
    ];

    const reply = await callCoach(model, apiKey, messages);
    await insertCoachChat(athleteId, 'web', 'assistant', reply || 'Sem resposta.');
    res.redirect('/coach');
  } catch (err) {
    res.redirect(`/coach?error=${encodeURIComponent(err.message)}`);
  }
});

app.post('/coach/feedback', async (req, res) => {
  const athleteId = String(req.body.athlete || ATHLETE_DEFAULT);
  try {
    await insertFeedback(athleteId, {
      session_date: String(req.body.session_date || '').trim(),
      perceived: String(req.body.perceived || '').trim(),
      rpe: String(req.body.rpe || '').trim(),
      conditions: String(req.body.conditions || '').trim(),
      notes: String(req.body.notes || '').trim(),
    });
    res.redirect('/coach');
  } catch (err) {
    res.redirect(`/coach?error=${encodeURIComponent(err.message)}`);
  }
});

app.post('/coach/reschedule', async (req, res) => {
  const athleteId = String(req.body.athlete || ATHLETE_DEFAULT);
  const fromDate = String(req.body.from_date || '').trim();
  const toDate = String(req.body.to_date || '').trim();
  if (!fromDate || !toDate) return res.redirect('/coach?error=Datas invalidas');
  try {
    await reschedulePlan(athleteId, fromDate, toDate);
    await insertCoachChat(
      athleteId,
      'web',
      'assistant',
      `Reagendado: ${fromDate} -> ${toDate}.`
    );
    res.redirect('/coach');
  } catch (err) {
    res.redirect(`/coach?error=${encodeURIComponent(err.message)}`);
  }
});

app.get('/activity/:id', async (req, res) => {
  const athleteId = String(req.query.athlete || ATHLETE_DEFAULT);
  const activityId = String(req.params.id);
  try {
    const profile = await getAthleteProfile(athleteId);
    if (!profile) return res.redirect('/setup');
    const weightLatest = await getLatestWeight(athleteId);
    const summaryRow = await runSql(
      `SELECT start_at, distance_km, duration_min, avg_hr, tags
       FROM session_log
       WHERE athlete_id='${sqlEscape(athleteId)}' AND activity_id='${sqlEscape(activityId)}'
       ORDER BY start_at DESC LIMIT 1;`
    );
    const [start_at, distance_km, duration_min, avg_hr, tags] = (summaryRow || '||||').split('|');
    res.render('activity', {
      profile,
      activityId,
      summary: { start_at, distance_km, duration_min, avg_hr, tags },
      weightLatest,
    });
  } catch (err) {
    res.status(500).send(`Erro ao carregar atividade: ${err.message}`);
  }
});

app.get('/api/activity/:id', async (req, res) => {
  const activityId = String(req.params.id);
  const config = await loadConfigMap();
  const influxUrl = config.INFLUX_URL || 'http://localhost:8086/query';
  const influxDb = config.INFLUX_DB || 'GarminStats';

  try {
    const url = new URL(influxUrl);
    const query = `SELECT * FROM "ActivityGPS" WHERE "ActivityID"='${activityId}' ORDER BY time ASC`;
    url.searchParams.set('db', influxDb);
    url.searchParams.set('q', query);

    const response = await fetch(url.toString());
    const payload = await response.json();
    const series = payload?.results?.[0]?.series?.[0];
    if (!series) return res.json({ points: [] });
    const columns = series.columns || [];
    const points = (series.values || []).map((row) => {
      const obj = {};
      for (let i = 0; i < columns.length; i += 1) {
        obj[columns[i]] = row[i];
      }
      return obj;
    });
    res.json({ points });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Ultra Coach Web rodando em http://localhost:${PORT}`);
});
