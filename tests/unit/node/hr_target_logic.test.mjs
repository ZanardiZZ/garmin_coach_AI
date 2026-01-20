import { describe, it, expect } from 'vitest';
import { buildSteps, fitHrValue } from '../../../fit/workout_to_fit_lib.mjs';

describe('fitHrValue - Conversão de HR para valor FIT', () => {
  it('adiciona +100 offset ao valor de HR', () => {
    expect(fitHrValue(125)).toBe(225);
    expect(fitHrValue(150)).toBe(250);
    expect(fitHrValue(180)).toBe(280);
  });

  it('arredonda valores decimais', () => {
    expect(fitHrValue(125.4)).toBe(225);
    expect(fitHrValue(125.6)).toBe(226);
  });

  it('retorna 0 para valores inválidos', () => {
    expect(fitHrValue(0)).toBe(0);
    expect(fitHrValue(-10)).toBe(0);
    expect(fitHrValue(NaN)).toBe(0);
    expect(fitHrValue(null)).toBe(0);
    expect(fitHrValue(undefined)).toBe(0);
    expect(fitHrValue('não-número')).toBe(0);
  });

  it('aceita números como string', () => {
    expect(fitHrValue('125')).toBe(225);
  });
});

describe('buildSteps - Lógica de HR targets', () => {
  it('usa z2_hr_cap de constraints quando segment não tem target_hr', () => {
    const workout = {
      segments: [
        { name: 'Main', duration_min: 30 },
      ],
    };

    const constraints = {
      z2_hr_cap: 150,
    };

    const steps = buildSteps(workout, constraints);

    expect(steps).toHaveLength(1);
    expect(steps[0].targetType).toBe('heartRate');
    expect(steps[0].customTargetHeartRateHigh).toBe(250); // 150 + 100
  });

  it('faz override de constraint com target_hr_high de segment', () => {
    const workout = {
      segments: [
        {
          name: 'Main',
          duration_min: 30,
          target_hr_high: 160,
        },
      ],
    };

    const constraints = {
      z2_hr_cap: 150,
    };

    const steps = buildSteps(workout, constraints);

    expect(steps).toHaveLength(1);
    expect(steps[0].customTargetHeartRateHigh).toBe(260); // 160 + 100 (override de segment)
  });

  it('usa target_hr_low e target_hr_high do segment', () => {
    const workout = {
      segments: [
        {
          name: 'Main',
          duration_min: 30,
          target_hr_low: 130,
          target_hr_high: 155,
        },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps).toHaveLength(1);
    expect(steps[0].targetType).toBe('heartRate');
    expect(steps[0].customTargetHeartRateLow).toBe(230); // 130 + 100
    expect(steps[0].customTargetHeartRateHigh).toBe(255); // 155 + 100
  });

  it('usa z3_hr_floor de constraints para target_hr_low quando segment não especifica', () => {
    const workout = {
      segments: [
        {
          name: 'Work',
          duration_min: 5,
          target_hr_high: 165,
        },
      ],
    };

    const constraints = {
      z2_hr_cap: 150,
      z3_hr_floor: 155,
    };

    const steps = buildSteps(workout, constraints);

    expect(steps).toHaveLength(1);
    expect(steps[0].customTargetHeartRateLow).toBe(255); // 155 + 100 (z3_floor)
    expect(steps[0].customTargetHeartRateHigh).toBe(265); // 165 + 100
  });

  it('omite customTargetHeartRateLow quando não há valor válido', () => {
    const workout = {
      segments: [
        {
          name: 'Main',
          duration_min: 30,
          target_hr_high: 150,
        },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps).toHaveLength(1);
    expect(steps[0].customTargetHeartRateLow).toBeUndefined();
    expect(steps[0].customTargetHeartRateHigh).toBe(250); // 150 + 100
  });

  it('usa targetType=open quando não há constraints nem targets', () => {
    const workout = {
      segments: [
        { name: 'Main', duration_min: 30 },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps).toHaveLength(1);
    expect(steps[0].targetType).toBe('open');
    expect(steps[0].customTargetHeartRateLow).toBeUndefined();
    expect(steps[0].customTargetHeartRateHigh).toBeUndefined();
  });

  it('aceita variações de nome de constraint (camelCase, snake_case)', () => {
    const workout = {
      segments: [{ name: 'Main', duration_min: 30 }],
    };

    // Testa z2_hr_cap
    let steps = buildSteps(workout, { z2_hr_cap: 150 });
    expect(steps[0].customTargetHeartRateHigh).toBe(250);

    // Testa z2Cap
    steps = buildSteps(workout, { z2Cap: 150 });
    expect(steps[0].customTargetHeartRateHigh).toBe(250);

    // Testa z2_cap
    steps = buildSteps(workout, { z2_cap: 150 });
    expect(steps[0].customTargetHeartRateHigh).toBe(250);
  });

  it('aceita variações de nome de target HR no segment', () => {
    const workout = {
      segments: [
        {
          name: 'Main',
          duration_min: 30,
          hr_low: 130,
          hr_high: 155,
        },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps).toHaveLength(1);
    expect(steps[0].customTargetHeartRateLow).toBe(230); // 130 + 100
    expect(steps[0].customTargetHeartRateHigh).toBe(255); // 155 + 100
  });

  it('seta targetHrZone=0 quando usa custom range', () => {
    const workout = {
      segments: [
        {
          name: 'Main',
          duration_min: 30,
          target_hr_low: 130,
          target_hr_high: 150,
        },
      ],
    };

    const steps = buildSteps(workout, {});

    expect(steps).toHaveLength(1);
    expect(steps[0].targetType).toBe('heartRate');
    expect(steps[0].targetHrZone).toBe(0); // 0 = custom
  });

  it('ignora target_hr_low=0 e usa z3_floor se disponível', () => {
    const workout = {
      segments: [
        {
          name: 'Main',
          duration_min: 30,
          target_hr_low: 0,
          target_hr_high: 165,
        },
      ],
    };

    const constraints = { z3_hr_floor: 155 };

    const steps = buildSteps(workout, constraints);

    expect(steps).toHaveLength(1);
    expect(steps[0].customTargetHeartRateLow).toBe(255); // 155 + 100 (z3_floor)
  });
});
