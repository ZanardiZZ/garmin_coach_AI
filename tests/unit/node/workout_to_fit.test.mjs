import { describe, it, expect } from 'vitest';
import {
  toMsFromMin,
  normTitle,
  intensityEnumFromName,
  buildSteps,
  createFitFile,
} from '../../../fit/workout_to_fit_lib.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

describe('toMsFromMin - Conversão de minutos para milissegundos', () => {
  it('converte minutos para milissegundos corretamente', () => {
    expect(toMsFromMin(1)).toBe(60000); // 1min = 60,000ms
    expect(toMsFromMin(5)).toBe(300000); // 5min = 300,000ms
    expect(toMsFromMin(60)).toBe(3600000); // 60min = 3,600,000ms
  });

  it('arredonda valores decimais', () => {
    expect(toMsFromMin(1.5)).toBe(90000); // 1.5min = 90,000ms
    expect(toMsFromMin(0.5)).toBe(30000); // 0.5min = 30,000ms
  });

  it('retorna 0 para valores inválidos', () => {
    expect(toMsFromMin(0)).toBe(0);
    expect(toMsFromMin(-5)).toBe(0);
    expect(toMsFromMin(NaN)).toBe(0);
    expect(toMsFromMin(null)).toBe(0);
    expect(toMsFromMin(undefined)).toBe(0);
    expect(toMsFromMin('não-número')).toBe(0);
  });

  it('aceita números como string', () => {
    expect(toMsFromMin('10')).toBe(600000);
  });
});

describe('normTitle - Normalização de título', () => {
  it('retorna string sem modificação para títulos normais', () => {
    expect(normTitle('Morning Run')).toBe('Morning Run');
    expect(normTitle('Treino Intervalado')).toBe('Treino Intervalado');
  });

  it('usa "Treino" como padrão para valores nulos', () => {
    expect(normTitle(null)).toBe('Treino');
    expect(normTitle(undefined)).toBe('Treino');
    expect(normTitle('')).toBe('Treino');
  });

  it('remove espaços em branco nas extremidades', () => {
    expect(normTitle('  Test  ')).toBe('Test');
    expect(normTitle('\tTest\n')).toBe('Test');
  });

  it('limita título a 60 caracteres', () => {
    const longTitle = 'A'.repeat(100);
    const result = normTitle(longTitle);
    expect(result.length).toBe(60);
    expect(result).toBe('A'.repeat(60));
  });

  it('converte tipos não-string para string', () => {
    expect(normTitle(123)).toBe('123');
    expect(normTitle(true)).toBe('true');
  });
});

describe('intensityEnumFromName - Detecção de intensidade por nome', () => {
  it('detecta warmup por palavras-chave', () => {
    expect(intensityEnumFromName('Aquecimento')).toBe('warmup');
    expect(intensityEnumFromName('aquecimento progressivo')).toBe('warmup');
    expect(intensityEnumFromName('AQUECIMENTO')).toBe('warmup');
  });

  it('detecta cooldown por palavras-chave', () => {
    expect(intensityEnumFromName('Desaquecimento')).toBe('cooldown');
    expect(intensityEnumFromName('cooldown final')).toBe('cooldown');
    expect(intensityEnumFromName('COOLDOWN')).toBe('cooldown');
  });

  it('detecta rest por palavras-chave', () => {
    expect(intensityEnumFromName('Recuperação')).toBe('rest');
    expect(intensityEnumFromName('Descanso')).toBe('rest');
    expect(intensityEnumFromName('rest interval')).toBe('rest');
    expect(intensityEnumFromName('RECUPERAÇÃO')).toBe('rest');
  });

  it('retorna active para outros casos', () => {
    expect(intensityEnumFromName('Main Set')).toBe('active');
    expect(intensityEnumFromName('Tiro Z3')).toBe('active');
    expect(intensityEnumFromName('Corrida contínua')).toBe('active');
    expect(intensityEnumFromName('')).toBe('active');
  });

  it('é case-insensitive', () => {
    expect(intensityEnumFromName('AQUECIMENTO')).toBe('warmup');
    expect(intensityEnumFromName('aquecimento')).toBe('warmup');
    expect(intensityEnumFromName('AqUeCiMeNtO')).toBe('warmup');
  });
});

describe('buildSteps - Construção de steps FIT', () => {
  it('gera steps básicos sem targets', () => {
    const workout = {
      segments: [
        { name: 'Warmup', duration_min: 10 },
        { name: 'Main', duration_min: 30 },
        { name: 'Cooldown', duration_min: 5 },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps).toHaveLength(3);
    expect(steps[0].wktStepName).toBe('Warmup');
    expect(steps[0].durationTime).toBe(600000); // 10min em ms
    expect(steps[0].intensity).toBe('warmup');
    expect(steps[1].durationTime).toBe(1800000); // 30min em ms
    expect(steps[2].intensity).toBe('cooldown');
  });

  it('pula segments com duration_min inválido', () => {
    const workout = {
      segments: [
        { name: 'Valid', duration_min: 10 },
        { name: 'Invalid', duration_min: 0 },
        { name: 'Also Invalid', duration_min: -5 },
        { name: 'Valid2', duration_min: 5 },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps).toHaveLength(2);
    expect(steps[0].wktStepName).toBe('Valid');
    expect(steps[1].wktStepName).toBe('Valid2');
  });

  it('seta messageIndex sequencialmente', () => {
    const workout = {
      segments: [
        { name: 'Step1', duration_min: 5 },
        { name: 'Step2', duration_min: 5 },
        { name: 'Step3', duration_min: 5 },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps[0].messageIndex).toBe(0);
    expect(steps[1].messageIndex).toBe(1);
    expect(steps[2].messageIndex).toBe(2);
  });

  it('usa durationType=time para todos os steps', () => {
    const workout = {
      segments: [
        { name: 'Main', duration_min: 30 },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps[0].durationType).toBe('time');
  });

  it('limita step name a 60 caracteres', () => {
    const longName = 'A'.repeat(100);
    const workout = {
      segments: [
        { name: longName, duration_min: 10 },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps[0].wktStepName.length).toBe(60);
  });

  it('usa "Step" como fallback para name ausente', () => {
    const workout = {
      segments: [
        { duration_min: 10 },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps[0].wktStepName).toBe('Step');
  });
});

describe('createFitFile - Geração de arquivo FIT', () => {
  it('gera buffer FIT com header válido', () => {
    const workout = {
      title: 'Test Workout',
      segments: [
        { name: 'Main', duration_min: 30 },
      ],
    };

    const buffer = createFitFile(workout, {});

    expect(buffer).toBeInstanceOf(Buffer);
    expect(buffer.length).toBeGreaterThan(0);

    // Verifica header FIT (bytes 8-11 devem ser ".FIT")
    const fitSignature = buffer.toString('utf8', 8, 12);
    expect(fitSignature).toBe('.FIT');
  });

  it('lança erro quando não há steps válidos', () => {
    const workout = {
      segments: [
        { name: 'Invalid', duration_min: 0 },
      ],
    };

    expect(() => createFitFile(workout, {})).toThrow('Nenhum step válido gerado');
  });

  it('escreve arquivo quando outputPath fornecido', () => {
    const workout = {
      title: 'Test Workout',
      segments: [
        { name: 'Main', duration_min: 30 },
      ],
    };

    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fit-test-'));
    const outputPath = path.join(tmpDir, 'test.fit');

    try {
      createFitFile(workout, {}, outputPath);

      expect(fs.existsSync(outputPath)).toBe(true);

      const content = fs.readFileSync(outputPath);
      const fitSignature = content.toString('utf8', 8, 12);
      expect(fitSignature).toBe('.FIT');
    } finally {
      // Cleanup
      if (fs.existsSync(outputPath)) {
        fs.unlinkSync(outputPath);
      }
      fs.rmdirSync(tmpDir);
    }
  });

  it('usa título do workout no FIT', () => {
    const workout = {
      title: 'Custom Title',
      segments: [
        { name: 'Main', duration_min: 30 },
      ],
    };

    // Apenas valida que não lança erro
    const buffer = createFitFile(workout, {});
    expect(buffer).toBeInstanceOf(Buffer);
  });

  it('usa workout_title como alternativa a title', () => {
    const workout = {
      workout_title: 'Alternative Title',
      segments: [
        { name: 'Main', duration_min: 30 },
      ],
    };

    const buffer = createFitFile(workout, {});
    expect(buffer).toBeInstanceOf(Buffer);
  });

  it('gera FIT com múltiplos segments', () => {
    const workout = {
      title: 'Multi Segment',
      segments: [
        { name: 'Warmup', duration_min: 10 },
        { name: 'Work1', duration_min: 5 },
        { name: 'Rest1', duration_min: 2 },
        { name: 'Work2', duration_min: 5 },
        { name: 'Cooldown', duration_min: 5 },
      ],
    };

    const buffer = createFitFile(workout, {});
    expect(buffer).toBeInstanceOf(Buffer);
    expect(buffer.length).toBeGreaterThan(100); // Arquivo deve ter tamanho razoável
  });
});
