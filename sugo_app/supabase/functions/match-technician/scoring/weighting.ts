/**
 * Turns a list of weighted factors into a stage score.
 *
 * ## The graceful-degradation rule
 *
 * A factor whose `value` is null is **unavailable**, not zero. TomTom being
 * down does not mean every technician is stuck in traffic. If we scored a
 * missing factor as 0 the whole field would drop by the same amount, the
 * ranking would be unchanged, and the printed scores would be lies.
 *
 * So `combine` drops null factors and redistributes their weight across the
 * survivors, keeping the remaining weights summing to 1. A stage score stays
 * on a 0..1 scale and stays comparable, whatever the outside world is doing.
 * The dropped factor simply never appears in the breakdown, and the UI shows
 * one fewer explainability chip.
 */
import type { ScoreFactor, StageResult } from "./types.ts";
import { clamp01 } from "./geo.ts";

export interface FactorInput {
  key: string;
  label: string;
  /** 0..1, or null when the input could not be measured. */
  value: number | null;
  /** Nominal weight from `constants.ts`, before renormalisation. */
  weight: number;
  note?: string;
}

export function combine(inputs: FactorInput[]): StageResult {
  const usable = inputs.filter(
    (input): input is FactorInput & { value: number } =>
      input.value !== null && input.value !== undefined &&
      !Number.isNaN(input.value),
  );

  if (usable.length === 0) {
    return { score: 0, factors: [] };
  }

  const nominalTotal = usable.reduce((sum, input) => sum + input.weight, 0);
  if (nominalTotal <= 0) return { score: 0, factors: [] };

  const factors: ScoreFactor[] = usable.map((input) => {
    // Renormalise so the surviving weights sum to 1 again.
    const weight = input.weight / nominalTotal;
    const value = clamp01(input.value);
    return {
      key: input.key,
      label: input.label,
      value: round(value),
      weight: round(weight),
      contribution: round(value * weight),
      note: input.note,
    };
  });

  const score = factors.reduce((sum, factor) => sum + factor.contribution, 0);

  return { score: round(clamp01(score)), factors };
}

/** Four decimals is plenty for a 0..1 score and keeps the jsonb readable. */
export function round(value: number, places = 4): number {
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
}
