import { describe, expect, it } from "vitest";
import {
  buildProgramSetVolumeReport,
  type CompletedSetEvent,
} from "../../src/domain/analytics/TrainingAnalytics";

describe("program set volume report", () => {
  it("normalizes completed program sets to average sets per week", () => {
    const events: CompletedSetEvent[] = [
      completedSet(1, 1, "Back"),
      completedSet(2, 1, "Back"),
      completedSet(3, 4, "Chest"),
      completedSet(4, 4, "Chest"),
      completedSet(5, 4, "Chest"),
    ];

    const report = buildProgramSetVolumeReport({
      events,
      programLengthWeeks: 4,
      focusMuscleIds: [1],
    });

    expect(report.totalCompletedSets).toBe(5);
    expect(report.rows).toEqual([
      {
        muscleId: 4,
        muscleName: "Chest",
        completedSets: 3,
        averageSetsPerWeek: 0.75,
        isFocusMuscle: false,
      },
      {
        muscleId: 1,
        muscleName: "Back",
        completedSets: 2,
        averageSetsPerWeek: 0.5,
        isFocusMuscle: true,
      },
    ]);
  });

  it("keeps alphabetical ordering when average volume ties", () => {
    const report = buildProgramSetVolumeReport({
      events: [completedSet(1, 2, "Biceps"), completedSet(2, 1, "Back")],
      programLengthWeeks: 2,
      focusMuscleIds: [],
    });

    expect(report.rows.map((row) => row.muscleName)).toEqual(["Back", "Biceps"]);
  });
});

function completedSet(setId: number, muscleId: number, muscleName: string): CompletedSetEvent {
  return {
    setId,
    muscleId,
    muscleName,
    completedAt: "2026-06-19T12:00:00.000Z",
  };
}
