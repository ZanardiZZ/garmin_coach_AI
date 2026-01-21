#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';

const DB = process.env.ULTRA_COACH_DB || '/var/lib/ultra-coach/coach.sqlite';
const KEY_PATH =
  process.env.ULTRA_COACH_KEY_PATH ||
  path.join(os.homedir(), '.ultra-coach', 'secret.key');

function usage() {
  console.error('Uso: config_set.mjs KEY VALUE');
  process.exit(2);
}

const keyArg = process.argv[2];
const valueArg = process.argv[3];
if (!keyArg) usage();

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

function sqlEscape(value) {
  return String(value ?? '').replace(/'/g, "''");
}

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

async function main() {
  const key = readKey();
  const enc = encryptValue(valueArg ?? '', key);
  const safeKey = sqlEscape(keyArg);
  const safeVal = sqlEscape(enc);
  await runSql(
    `CREATE TABLE IF NOT EXISTS config_kv (
      key TEXT PRIMARY KEY,
      value_enc TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT
    );`
  );
  await runSql(
    `INSERT INTO config_kv (key, value_enc, created_at, updated_at)
     VALUES ('${safeKey}', '${safeVal}', datetime('now'), datetime('now'))
     ON CONFLICT(key) DO UPDATE SET value_enc=excluded.value_enc, updated_at=datetime('now');`
  );
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
