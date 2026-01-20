#!/usr/bin/env node
/*
  workout_to_fit.mjs

  Dependencia: @garmin/fitsdk

  Uso:
    node workout_to_fit.mjs --in workout.json --out workout.fit --constraints constraints.json

  - constraints.json (opcional) pode conter:
      {"z2_hr_cap":143,"z3_hr_floor":152}

  Observacoes:
  - Este gerador foca em Workouts (FIT file_id.type=workout).
  - Steps sao baseados em tempo (ms) e alvo por FC (custom range) quando possivel.
*/

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

import { Encoder, Profile } from '@garmin/fitsdk';

// ---------- Helpers ----------

function log(level, msg) {
  const ts = new Date().toISOString();
  const prefix = `[${ts}][fit][${level}]`;
  if (level === 'ERR') {
    console.error(`${prefix} ${msg}`);
  } else {
    console.log(`${prefix} ${msg}`);
  }
}

function arg(name, def = null) {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return def;
  return process.argv[idx + 1] ?? def;
}

function fileExists(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.R_OK);
    return true;
  } catch {
    return false;
  }
}

function readJsonFile(filePath, description) {
  if (!fileExists(filePath)) {
    throw new Error(`Arquivo ${description} não encontrado: ${filePath}`);
  }

  let content;
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    throw new Error(`Erro ao ler ${description}: ${err.message}`);
  }

  if (!content.trim()) {
    throw new Error(`Arquivo ${description} está vazio: ${filePath}`);
  }

  try {
    return JSON.parse(content);
  } catch (err) {
    throw new Error(`JSON inválido em ${description}: ${err.message}`);
  }
}

function validateWorkout(workout) {
  const errors = [];

  if (!workout || typeof workout !== 'object') {
    errors.push('Workout deve ser um objeto JSON válido');
    return errors;
  }

  if (!workout.segments) {
    errors.push('Campo "segments" é obrigatório');
  } else if (!Array.isArray(workout.segments)) {
    errors.push('Campo "segments" deve ser um array');
  } else if (workout.segments.length === 0) {
    errors.push('Array "segments" não pode estar vazio');
  } else {
    workout.segments.forEach((seg, i) => {
      if (!seg.name) {
        errors.push(`Segment[${i}]: campo "name" é obrigatório`);
      }
      if (seg.duration_min === undefined || seg.duration_min === null) {
        errors.push(`Segment[${i}]: campo "duration_min" é obrigatório`);
      } else if (typeof seg.duration_min !== 'number' || seg.duration_min <= 0) {
        errors.push(`Segment[${i}]: "duration_min" deve ser número positivo`);
      }
    });
  }

  return errors;
}

function toMsFromMin(min) {
  const n = Number(min);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.round(n * 60 * 1000);
}

function normTitle(s) {
  return String(s ?? 'Treino').trim().slice(0, 60);
}

function intensityEnumFromName(name = '') {
  const n = String(name).toLowerCase();
  if (n.includes('aquec')) return 'warmup';
  if (n.includes('desaquec') || n.includes('cool')) return 'cooldown';
  if (n.includes('recuper') || n.includes('descanso') || n.includes('rest')) return 'rest';
  return 'active';
}

// FIT: valores especificos de FC precisam ser somados a +100.
// (ex.: 125 bpm -> 225)
function fitHrValue(bpm) {
  const n = Number(bpm);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.round(n + 100);
}

function buildSteps(workout, constraints) {
  const steps = [];
  const segs = Array.isArray(workout.segments) ? workout.segments : [];

  const z2Cap = Number(constraints?.z2_hr_cap ?? constraints?.z2Cap ?? constraints?.z2_cap);
  const z3Floor = Number(constraints?.z3_hr_floor ?? constraints?.z3Floor ?? constraints?.z3_floor);

  for (const seg of segs) {
    const name = String(seg?.name ?? 'Step').trim().slice(0, 60);
    const durMs = toMsFromMin(seg?.duration_min);
    if (!durMs) continue;

    // alvo por FC: se o JSON do treino trouxer hr_low/hr_high, usa; senao aplica cap de Z2 quando existir.
    const hrLow = Number(seg?.target_hr_low ?? seg?.hr_low);
    const hrHigh = Number(seg?.target_hr_high ?? seg?.hr_high);

    let targetType = 'open';
    let targetHrZone = undefined;
    let customLow = undefined;
    let customHigh = undefined;

    if (Number.isFinite(hrLow) || Number.isFinite(hrHigh) || Number.isFinite(z2Cap) || Number.isFinite(z3Floor)) {
      // Se tiver qualquer indicacao de FC, usamos target_type=heart_rate (custom)
      targetType = 'heartRate';
      targetHrZone = 0; // 0 => custom (ver exemplos)

      const low = Number.isFinite(hrLow) && hrLow > 0 ? hrLow : (Number.isFinite(z3Floor) ? z3Floor : 0);
      const high = Number.isFinite(hrHigh) && hrHigh > 0 ? hrHigh : (Number.isFinite(z2Cap) ? z2Cap : 0);

      if (low > 0) customLow = fitHrValue(low);
      if (high > 0) customHigh = fitHrValue(high);

      // Se so temos cap (high) e low ficou 0, deixamos customLow omitido.
    }

    const intensity = intensityEnumFromName(name);

    const step = {
      mesgNum: Profile.MesgNum.WORKOUT_STEP,
      messageIndex: steps.length,
      wktStepName: name,
      durationType: 'time',
      durationTime: durMs,
      targetType,
      intensity,
    };

    // Campos dinamicos para alvo por FC custom.
    if (targetType === 'heartRate') {
      // targetHrZone e customTargetHeartRateLow/High sao os nomes camelCase do perfil.
      step.targetHrZone = targetHrZone;
      if (customLow !== undefined) step.customTargetHeartRateLow = customLow;
      if (customHigh !== undefined) step.customTargetHeartRateHigh = customHigh;
    }

    steps.push(step);
  }

  return steps;
}

function showUsage() {
  console.log(`
Uso: node workout_to_fit.mjs [opções]

Opções:
  --in, -i <arquivo>          Arquivo JSON do workout (obrigatório)
  --out, -o <arquivo>         Arquivo FIT de saída (default: workout.fit)
  --constraints, -c <arquivo> Arquivo JSON com constraints de FC (opcional)
  --help, -h                  Mostra esta ajuda

Exemplo:
  node workout_to_fit.mjs --in treino.json --out treino.fit --constraints limits.json
`);
}

function main() {
  // Verifica ajuda
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    showUsage();
    process.exit(0);
  }

  const inFile = arg('--in', arg('-i'));
  const outFile = arg('--out', arg('-o', 'workout.fit'));
  const constraintsFile = arg('--constraints', arg('-c'));

  // Valida argumentos
  if (!inFile) {
    log('ERR', 'Arquivo de entrada não especificado. Use --in <arquivo>');
    showUsage();
    process.exit(2);
  }

  // Lê e valida workout
  let workout;
  try {
    workout = readJsonFile(inFile, 'workout');
  } catch (err) {
    log('ERR', err.message);
    process.exit(1);
  }

  const validationErrors = validateWorkout(workout);
  if (validationErrors.length > 0) {
    log('ERR', 'Workout inválido:');
    validationErrors.forEach(e => console.error(`  - ${e}`));
    process.exit(1);
  }

  // Lê constraints (opcional)
  let constraints = {};
  if (constraintsFile) {
    try {
      constraints = readJsonFile(constraintsFile, 'constraints');
    } catch (err) {
      log('WARN', `Constraints não carregados: ${err.message}`);
      // Continua sem constraints
    }
  }

  // Gera steps
  const title = normTitle(workout.workout_title ?? workout.title);
  const steps = buildSteps(workout, constraints);

  if (!steps.length) {
    log('ERR', 'Nenhum step válido gerado (segments vazios ou duration_min inválido)');
    process.exit(1);
  }

  // Gera arquivo FIT
  let encoder;
  try {
    encoder = new Encoder();

    // 1) file_id: para workout, basta setar type.
    encoder.writeMesg({
      mesgNum: Profile.MesgNum.FILE_ID,
      type: 'workout',
    });

    // 2) workout summary
    encoder.writeMesg({
      mesgNum: Profile.MesgNum.WORKOUT,
      wktName: title,
      sport: 'running',
      numValidSteps: steps.length,
    });

    // 3) steps
    for (const s of steps) encoder.writeMesg(s);

    const bytes = encoder.close();

    // Escreve arquivo
    const outDir = path.dirname(outFile);
    if (outDir && outDir !== '.' && !fs.existsSync(outDir)) {
      fs.mkdirSync(outDir, { recursive: true });
    }

    fs.writeFileSync(outFile, Buffer.from(bytes));
    log('INFO', `Gerado: ${path.resolve(outFile)} (steps=${steps.length}, title="${title}")`);

  } catch (err) {
    log('ERR', `Falha ao gerar FIT: ${err.message}`);
    process.exit(1);
  }
}

main();
