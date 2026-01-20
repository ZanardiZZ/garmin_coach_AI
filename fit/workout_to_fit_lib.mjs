/*
  workout_to_fit_lib.mjs

  Funções exportáveis do workout_to_fit.mjs para testes.
  Este arquivo contém a lógica de negócio sem o main(), permitindo testes unitários.
*/

import fs from 'node:fs';
import { Encoder, Profile } from '@garmin/fitsdk';

export function validateWorkout(workout) {
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

export function toMsFromMin(min) {
  const n = Number(min);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.round(n * 60 * 1000);
}

export function normTitle(s) {
  return String(s ?? 'Treino').trim().slice(0, 60);
}

export function intensityEnumFromName(name = '') {
  const n = String(name).toLowerCase();
  if (n.includes('aquec')) return 'warmup';
  if (n.includes('desaquec') || n.includes('cool')) return 'cooldown';
  if (n.includes('recuper') || n.includes('descanso') || n.includes('rest')) return 'rest';
  return 'active';
}

export function fitHrValue(bpm) {
  const n = Number(bpm);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.round(n + 100);
}

export function buildSteps(workout, constraints) {
  const steps = [];
  const segs = Array.isArray(workout.segments) ? workout.segments : [];

  const z2Cap = Number(constraints?.z2_hr_cap ?? constraints?.z2Cap ?? constraints?.z2_cap);
  const z3Floor = Number(constraints?.z3_hr_floor ?? constraints?.z3Floor ?? constraints?.z3_floor);

  for (const seg of segs) {
    const name = String(seg?.name ?? 'Step').trim().slice(0, 60);
    const durMs = toMsFromMin(seg?.duration_min);
    if (!durMs) continue;

    const hrLow = Number(seg?.target_hr_low ?? seg?.hr_low);
    const hrHigh = Number(seg?.target_hr_high ?? seg?.hr_high);

    let targetType = 'open';
    let targetHrZone = undefined;
    let customLow = undefined;
    let customHigh = undefined;

    if (Number.isFinite(hrLow) || Number.isFinite(hrHigh) || Number.isFinite(z2Cap) || Number.isFinite(z3Floor)) {
      targetType = 'heartRate';
      targetHrZone = 0;

      const low = Number.isFinite(hrLow) && hrLow > 0 ? hrLow : (Number.isFinite(z3Floor) ? z3Floor : 0);
      const high = Number.isFinite(hrHigh) && hrHigh > 0 ? hrHigh : (Number.isFinite(z2Cap) ? z2Cap : 0);

      if (low > 0) customLow = fitHrValue(low);
      if (high > 0) customHigh = fitHrValue(high);
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

    if (targetType === 'heartRate') {
      step.targetHrZone = targetHrZone;
      if (customLow !== undefined) step.customTargetHeartRateLow = customLow;
      if (customHigh !== undefined) step.customTargetHeartRateHigh = customHigh;
    }

    steps.push(step);
  }

  return steps;
}

export function createFitFile(workout, constraints, outputPath) {
  const title = normTitle(workout.workout_title ?? workout.title);
  const steps = buildSteps(workout, constraints);

  if (!steps.length) {
    throw new Error('Nenhum step válido gerado (segments vazios ou duration_min inválido)');
  }

  const encoder = new Encoder();

  // 1) file_id
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

  // Escreve arquivo se outputPath fornecido
  if (outputPath) {
    fs.writeFileSync(outputPath, Buffer.from(bytes));
  }

  return Buffer.from(bytes);
}
