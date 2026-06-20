import { describe, expect, it } from "vitest";
import {
  buildProgramOverviewSegments,
  buildProgramSchedule,
  calculateProgramProgress,
  createProgramOverviewStatusCounts,
  markActiveProgramSchedule,
  type PersistedProgramScheduleCell,
} from "../../src/domain/programs/ProgramOverview";

describe("program overview", () => {
  it("builds a full schedule grid from persisted and synthesized planned cells", () => {
    const persistedCells: PersistedProgramScheduleCell[] = [
      {
        workoutId: 10,
        week: 1,
        day: 1,
        totalSets: 4,
        statusCounts: createProgramOverviewStatusCounts({ complete: 4 }),
      },
      {
        workoutId: 11,
        week: 1,
        day: 2,
        totalSets: 2,
        statusCounts: createProgramOverviewStatusCounts({ active: 2 }),
      },
    ];

    const schedule = buildProgramSchedule({
      programLengthWeeks: 3,
      workoutsPerWeek: 2,
      persistedCells,
      plannedSetCountsByDay: new Map([
        [1, 4],
        [2, 2],
      ]),
    });

    expect(schedule).toHaveLength(6);
    expect(schedule[0]).toEqual(expect.objectContaining({ workoutId: 10, source: "persisted" }));
    expect(schedule[1]).toEqual(expect.objectContaining({ workoutId: 11, source: "persisted" }));
    expect(schedule[2]).toMatchObject({
      workoutId: null,
      week: 2,
      day: 1,
      source: "planned",
      totalSets: 4,
    });
    expect(schedule[2]?.statusCounts.planned).toBe(4);
    expect(schedule[5]).toEqual(expect.objectContaining({ week: 3, day: 2, totalSets: 2 }));
  });

  it("calculates progress from completed sets without hiding halted progress", () => {
    const schedule = buildProgramSchedule({
      programLengthWeeks: 2,
      workoutsPerWeek: 2,
      persistedCells: [
        {
          workoutId: 10,
          week: 1,
          day: 1,
          totalSets: 4,
          statusCounts: createProgramOverviewStatusCounts({ complete: 3, halted: 1 }),
        },
      ],
      plannedSetCountsByDay: new Map([
        [1, 4],
        [2, 2],
      ]),
    });

    expect(calculateProgramProgress(schedule)).toEqual({
      completedSets: 3,
      totalSets: 12,
      progressPercent: 25,
    });
  });

  it("marks active cells only when the active workout belongs to the displayed program", () => {
    const schedule = buildProgramSchedule({
      programLengthWeeks: 1,
      workoutsPerWeek: 2,
      persistedCells: [
        {
          workoutId: 10,
          week: 1,
          day: 1,
          totalSets: 2,
          statusCounts: createProgramOverviewStatusCounts({ active: 2 }),
        },
      ],
      plannedSetCountsByDay: new Map([[1, 2]]),
    });

    expect(
      markActiveProgramSchedule({
        schedule,
        displayedProgramId: 1,
        activeProgramId: 1,
        activeWorkoutId: 10,
      })[0]?.isActive,
    ).toBe(true);
    expect(
      markActiveProgramSchedule({
        schedule,
        displayedProgramId: 1,
        activeProgramId: 2,
        activeWorkoutId: 10,
      })[0]?.isActive,
    ).toBe(false);
  });

  it("builds proportional complete skipped and halted segments", () => {
    const segments = buildProgramOverviewSegments({
      workoutId: 10,
      week: 1,
      day: 1,
      source: "persisted",
      totalSets: 10,
      statusCounts: createProgramOverviewStatusCounts({
        complete: 7,
        skipped: 2,
        halted: 1,
      }),
    });

    expect(segments).toEqual([
      { status: "complete", count: 7, widthPercent: 70 },
      { status: "skipped", count: 2, widthPercent: 20 },
      { status: "halted", count: 1, widthPercent: 10 },
    ]);
  });
});
