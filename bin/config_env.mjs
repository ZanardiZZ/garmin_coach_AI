#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFile } from 'node:child_process';
import crypto from 'node:crypto';

const DB = process.env.ULTRA_COACH_DB || '/var/lib/ultra-coach/coach.sqlite';
const KEY_PATH =
  process.env.ULTRA_COACH_KEY_PATH ||
  path.join(os.homedir(), '.ultra-coach', 'secret.key');

function readKey() {
  if (!fs.existsSync(KEY_PATH)) return null;
  const raw = fs.readFileSync(KEY_PATH, 'utf8').trim();
  if (!raw) return null;
  return Buffer.from(raw, 'base64');
}

function shellEscape(value) {
  const s = String(value ?? '');
  return `'${s.replace(/'/g, `'\"'\"'`)}'`;
}

function decryptValue(enc, key) {
  const parts = String(enc || '').split(':');
  if (parts.length !== 4 || parts[0] !== 'v1') {
    throw new Error('Formato invalido');
  }
  const iv = Buffer.from(parts[1], 'base64');
  const tag = Buffer.from(parts[2], 'base64');
  const data = Buffer.from(parts[3], 'base64');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const decrypted = Buffer.concat([decipher.update(data), decipher.final()]);
  return decrypted.toString('utf8');
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
  if (!key || key.length !== 32) {
    process.exit(0);
  }

  let rows = '';
  try {
    rows = await runSql('SELECT key, value_enc FROM config_kv;');
  } catch {
    process.exit(0);
  }
  if (!rows) process.exit(0);

  for (const line of rows.split('\n')) {
    const [k, v] = line.split('|');
    if (!k || !v) continue;
    try {
      const val = decryptValue(v, key);
      process.stdout.write(`export ${k}=${shellEscape(val)}\n`);
    } catch {
      continue;
    }
  }
}

main();
