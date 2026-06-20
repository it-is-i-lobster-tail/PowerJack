import { describe, expect, it } from "vitest";
import {
  buildProgramSetVolumeReport,
  type CompletedSetEvent,
} from "../../src/domain/analytics/TrainingAnalytics";

describe("program set volume report", () => {
  it("normalizes credited muscle sets to average sets per elapsed week", () => {
    const events: CompletedSetEvent[] = [
      completedSet(1, 1, "Back"),
      completedSet(1, 2, "Biceps", 0.5),
      completedSet(2, 1, "Back"),
      completedSet(2, 2, "Biceps", 0.5),
      completedSet(3, 4, "Chest"),
    ];

    const report = buildProgramSetVolumeReport({
      events,
      elapsedWeeks: 2,
      focusMuscleIds: [1],
    });

    expect(report.totalCompletedSets).toBe(3);
    expect(report.rows).toEqual([
      {
        muscleId: 1,
        muscleName: "Back",
        completedSets: 2,
        averageSetsPerWeek: 1,
        isFocusMuscle: true,
      },
      {
        muscleId: 2,
        muscleName: "Biceps",
        completedSets: 1,
        averageSetsPerWeek: 0.5,
        isFocusMuscle: false,
      },
      {
        muscleId: 4,
        muscleName: "Chest",
        completedSets: 1,
        averageSetsPerWeek: 0.5,
        isFocusMuscle: false,
      },
    ]);
  });

  it("keeps alphabetical ordering when average volume ties", () => {
    const report = buildProgramSetVolumeReport({
      events: [completedSet(1, 2, "Biceps"), completedSet(2, 1, "Back")],
      elapsedWeeks: 2,
      focusMuscleIds: [],
    });

    expect(report.rows.map((row) => row.muscleName)).toEqual(["Back", "Biceps"]);
  });
});

function completedSet(setId: number, muscleId: number, muscleName: string, setCredit = 1): CompletedSetEvent {
  return {
    setId,
    muscleId,
    muscleName,
    completedAt: "2026-06-19T12:00:00.000Z",
    setCredit,
  };
}
