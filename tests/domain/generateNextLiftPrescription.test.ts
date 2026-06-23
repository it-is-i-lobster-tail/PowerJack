import { describe, expect, it } from "vitest";
import {
  generateNextLiftPrescription,
  type GenerateNextLiftPrescriptionInput,
  type ProgressionLiftHistory,
} from "../../src/domain/workouts/progression/generateNextLiftPrescription";

const exercise = {
  minRepsHypertrophy: 6,
  maxRepsHypertrophy: 12,
  primaryMuscleId: 4,
  repsOnly: false,
};

describe("generateNextLiftPrescription", () => {
  it("uses the high-pain override and requires manual check-in", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ id: 20, pain: 4, effort: 3, reps: [8, 7], weight: 100 }) }),
    );

    expect(result).toEqual({
      gate: "gate_1_high_pain",
      manualCheckinSourceLiftId: 20,
      sets: [
        { order: 1, plannedReps: 8, plannedWeight: 100 },
        { order: 2, plannedReps: 7, plannedWeight: 100 },
      ],
    });
  });

  it("keeps one under-minimum set when exactly one set is below minimum", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ pain: 1, effort: 3, reps: [10, 5], weight: 100 }) }),
    );

    expect(result.gate).toBe("gate_2_under_minimum");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 10, plannedWeight: 100 },
      { order: 2, plannedReps: 6, plannedWeight: 100 },
    ]);
  });

  it("removes extra under-minimum sets and keeps successful sets", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ pain: 1, effort: 3, reps: [10, 5, 4], weight: 100 }) }),
    );

    expect(result.gate).toBe("gate_2_under_minimum");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 10, plannedWeight: 100 },
      { order: 2, plannedReps: 6, plannedWeight: 100 },
    ]);
  });

  it("repeats the lift for moderate pain after under-minimum checks pass", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ pain: 3, effort: 3, reps: [10, 8], weight: 125 }) }),
    );

    expect(result.gate).toBe("gate_3_moderate_pain");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 10, plannedWeight: 125 },
      { order: 2, plannedReps: 8, plannedWeight: 125 },
    ]);
  });

  it("repeats the lift for maximum effort", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ pain: 1, effort: 5, reps: [10, 8], weight: 125 }) }),
    );

    expect(result.gate).toBe("gate_4_max_effort");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 10, plannedWeight: 125 },
      { order: 2, plannedReps: 8, plannedWeight: 125 },
    ]);
  });

  it("adds one set for focus muscles after two eligible exposures", () => {
    const result = generateNextLiftPrescription(
      input({
        current: lift({ week: 2, pain: 1, effort: 2, reps: [10, 8], weight: 135 }),
        previous: lift({ week: 1, pain: 1, effort: 2, reps: [9, 8], weight: 130 }),
        focusMuscleIds: [4],
        programLengthWeeks: 8,
      }),
    );

    expect(result.gate).toBe("gate_5_focus_volume");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 10, plannedWeight: 135 },
      { order: 2, plannedReps: 8, plannedWeight: 135 },
      { order: 3, plannedReps: null, plannedWeight: 135 },
    ]);
  });

  it("adds one set for non-focus muscles after three eligible exposures", () => {
    const result = generateNextLiftPrescription(
      input({
        current: lift({ week: 3, pain: 1, effort: 3, reps: [10, 8], weight: 135 }),
        previous: lift({ week: 2, pain: 1, effort: 2, reps: [9, 8], weight: 130 }),
        twoWeeksAgo: lift({ week: 1, pain: 1, effort: 2, reps: [8, 8], weight: 125 }),
        focusMuscleIds: [1],
        programLengthWeeks: 8,
      }),
    );

    expect(result.gate).toBe("gate_6_non_focus_volume");
    expect(result.sets).toHaveLength(3);
    expect(result.sets[2]).toEqual({ order: 3, plannedReps: null, plannedWeight: 135 });
  });

  it("adds load when every set reaches the load threshold and the jump is within ten percent", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ pain: 1, effort: 4, reps: [12, 11], weight: 185 }) }),
    );

    expect(result.gate).toBe("gate_7_load");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 12, plannedWeight: 190 },
      { order: 2, plannedReps: 11, plannedWeight: 190 },
    ]);
  });

  it("adds reps when load progression is not ready", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ pain: 1, effort: 4, reps: [10, 8], weight: 185 }) }),
    );

    expect(result.gate).toBe("gate_7_reps");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 11, plannedWeight: 185 },
      { order: 2, plannedReps: 9, plannedWeight: 185 },
    ]);
  });

  it("uses every completed working set when a lifter manually adds volume", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ pain: 1, effort: 4, reps: [10, 8, 7], weight: 185 }) }),
    );

    expect(result.gate).toBe("gate_7_reps");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 11, plannedWeight: 185 },
      { order: 2, plannedReps: 9, plannedWeight: 185 },
      { order: 3, plannedReps: 8, plannedWeight: 185 },
    ]);
  });

  it("holds max reps when the five pound jump would exceed ten percent", () => {
    const result = generateNextLiftPrescription(
      input({ current: lift({ pain: 1, effort: 4, reps: [12, 12], weight: 40 }) }),
    );

    expect(result.gate).toBe("gate_7_reps");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 12, plannedWeight: 40 },
      { order: 2, plannedReps: 12, plannedWeight: 40 },
    ]);
  });

  it("progresses reps-only lifts without adding or carrying weight", () => {
    const result = generateNextLiftPrescription(
      input({
        current: lift({ pain: 1, effort: 4, reps: [20, 18], weight: null }),
        exercise: {
          minRepsHypertrophy: 8,
          maxRepsHypertrophy: 25,
          primaryMuscleId: 4,
          repsOnly: true,
        },
      }),
    );

    expect(result.gate).toBe("gate_7_reps");
    expect(result.sets).toEqual([
      { order: 1, plannedReps: 21, plannedWeight: null },
      { order: 2, plannedReps: 19, plannedWeight: null },
    ]);
  });

  it("carries skipped manual-check-in lifts forward", () => {
    const result = generateNextLiftPrescription(
      input({
        current: {
          ...lift({ id: 40, pain: null, effort: null, reps: [8, 7], weight: 100, status: "skipped" }),
          manualCheckinSourceLiftId: 20,
          sets: [
            set({ order: 1, plannedReps: 8, plannedWeight: 100, status: "skipped" }),
            set({ order: 2, plannedReps: 7, plannedWeight: 100, status: "skipped" }),
          ],
        },
      }),
    );

    expect(result).toEqual({
      gate: "skipped_carry_forward",
      manualCheckinSourceLiftId: 20,
      sets: [
        { order: 1, plannedReps: 8, plannedWeight: 100 },
        { order: 2, plannedReps: 7, plannedWeight: 100 },
      ],
    });
  });
});

function input(
  overrides: Partial<GenerateNextLiftPrescriptionInput> & { current: ProgressionLiftHistory },
): GenerateNextLiftPrescriptionInput {
  return {
    previous: null,
    twoWeeksAgo: null,
    exercise,
    focusMuscleIds: [],
    programLengthWeeks: 8,
    ...overrides,
  };
}

function lift({
  id = 1,
  week = 1,
  pain,
  effort,
  reps,
  weight,
  status = "completed",
}: {
  id?: number;
  week?: number;
  pain: number | null;
  effort: number | null;
  reps: number[];
  weight: number | null;
  status?: ProgressionLiftHistory["status"];
}): ProgressionLiftHistory {
  return {
    id,
    programWeek: week,
    status,
    levelOfPain: pain,
    levelOfEffort: effort,
    manualCheckinSourceLiftId: null,
    sets: reps.map((actualReps, index) =>
      set({
        order: index + 1,
        actualReps,
        actualWeight: weight,
        status,
      }),
    ),
  };
}

function set({
  order,
  actualReps = null,
  actualWeight = null,
  plannedReps = null,
  plannedWeight = null,
  status = "completed",
}: {
  order: number;
  actualReps?: number | null;
  actualWeight?: number | null;
  plannedReps?: number | null;
  plannedWeight?: number | null;
  status?: ProgressionLiftHistory["status"];
}) {
  return {
    order,
    plannedReps,
    plannedWeight,
    actualReps,
    actualWeight,
    status,
  };
}
