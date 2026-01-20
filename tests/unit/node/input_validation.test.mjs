import { describe, it, expect } from 'vitest';
import { validateWorkout } from '../../../fit/workout_to_fit_lib.mjs';

describe('validateWorkout - Validação de entrada', () => {
  it('valida que workout válido não retorna erros', () => {
    const workout = {
      segments: [
        { name: 'Aquecimento', duration_min: 10 },
        { name: 'Principal', duration_min: 30 },
      ],
    };

    const errors = validateWorkout(workout);
    expect(errors).toEqual([]);
  });

  it('rejeita workout nulo', () => {
    const errors = validateWorkout(null);
    expect(errors).toContain('Workout deve ser um objeto JSON válido');
  });

  it('rejeita workout undefined', () => {
    const errors = validateWorkout(undefined);
    expect(errors).toContain('Workout deve ser um objeto JSON válido');
  });

  it('rejeita workout que não é objeto', () => {
    const errors = validateWorkout('string');
    expect(errors).toContain('Workout deve ser um objeto JSON válido');
  });

  it('rejeita workout sem campo segments', () => {
    const workout = { title: 'Test' };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Campo "segments" é obrigatório');
  });

  it('rejeita workout com segments não-array', () => {
    const workout = { segments: 'not-an-array' };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Campo "segments" deve ser um array');
  });

  it('rejeita workout com segments vazio', () => {
    const workout = { segments: [] };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Array "segments" não pode estar vazio');
  });

  it('rejeita segment sem campo name', () => {
    const workout = {
      segments: [
        { duration_min: 10 }, // falta name
      ],
    };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Segment[0]: campo "name" é obrigatório');
  });

  it('rejeita segment sem campo duration_min', () => {
    const workout = {
      segments: [
        { name: 'Test' }, // falta duration_min
      ],
    };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Segment[0]: campo "duration_min" é obrigatório');
  });

  it('rejeita segment com duration_min null', () => {
    const workout = {
      segments: [
        { name: 'Test', duration_min: null },
      ],
    };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Segment[0]: campo "duration_min" é obrigatório');
  });

  it('rejeita segment com duration_min não-numérico', () => {
    const workout = {
      segments: [
        { name: 'Test', duration_min: 'dez' },
      ],
    };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Segment[0]: "duration_min" deve ser número positivo');
  });

  it('rejeita segment com duration_min zero', () => {
    const workout = {
      segments: [
        { name: 'Test', duration_min: 0 },
      ],
    };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Segment[0]: "duration_min" deve ser número positivo');
  });

  it('rejeita segment com duration_min negativo', () => {
    const workout = {
      segments: [
        { name: 'Test', duration_min: -5 },
      ],
    };
    const errors = validateWorkout(workout);
    expect(errors).toContain('Segment[0]: "duration_min" deve ser número positivo');
  });

  it('acumula múltiplos erros de validação', () => {
    const workout = {
      segments: [
        { name: 'Valid', duration_min: 10 },
        { duration_min: 5 }, // falta name
        { name: 'Test' }, // falta duration_min
        { name: 'Test2', duration_min: -1 }, // duration_min inválido
      ],
    };

    const errors = validateWorkout(workout);
    expect(errors.length).toBeGreaterThan(1);
    expect(errors).toContain('Segment[1]: campo "name" é obrigatório');
    expect(errors).toContain('Segment[2]: campo "duration_min" é obrigatório');
    expect(errors).toContain('Segment[3]: "duration_min" deve ser número positivo');
  });

  it('aceita workout com campos opcionais', () => {
    const workout = {
      title: 'Treino Test',
      description: 'Descrição longa',
      segments: [
        {
          name: 'Aquecimento',
          duration_min: 10,
          target_hr_low: 120,
          target_hr_high: 140,
          intensity: 'warmup',
        },
      ],
    };

    const errors = validateWorkout(workout);
    expect(errors).toEqual([]);
  });
});
