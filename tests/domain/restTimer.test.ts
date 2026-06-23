import { describe, expect, it } from "vitest";
import {
  createCancelledRestTimer,
  createIdleRestTimer,
  createRunningRestTimer,
  formatRestTimerRemaining,
  normalizeRestTimer,
  shouldDisplayRestTimer,
} from "../../src/domain/app-state/restTimer";
import {
  didAnySetBecomeComplete,
  didAnySetBecomeIncomplete,
  findNextIncompleteRestTimerTarget,
  findRestTimerTargetBySetId,
} from "../../src/domain/workouts/restTimerTarget";
import type {
  ActiveWorkoutLiftView,
  ActiveWorkoutSetView,
  ActiveWorkoutView,
  Workout,
} from "../../src/domain/workouts/Workout";
import type { Program } from "../../src/domain/programs/Program";

describe("rest timer", () => {
  it("normalizes running timers from wall-clock time and clamps at zero", () => {
    const timer = createRunningRestTimer({
      workoutId: 10,
      liftId: 20,
      nextSetId: 31,
      startedAt: "2026-06-21T19:00:00.000Z",
      durationSeconds: 120,
    });

    expect(normalizeRestTimer(timer, new Date("2026-06-21T19:00:18.000Z"))).toMatchObject({
      state: "running",
      remainingSeconds: 102,
    });
    expect(normalizeRestTimer(timer, new Date("2026-06-21T19:02:05.000Z"))).toMatchObject({
      state: "expired",
      remainingSeconds: 0,
    });
    expect(formatRestTimerRemaining(-12)).toBe("0:00");
    expect(formatRestTimerRemaining(102)).toBe("1:42");
  });

  it("displays only active timer states with complete ids", () => {
    expect(shouldDisplayRestTimer(createIdleRestTimer())).toBe(false);
    expect(shouldDisplayRestTimer(createCancelledRestTimer())).toBe(false);
    expect(
      shouldDisplayRestTimer(
        createRunningRestTimer({
          workoutId: 10,
          liftId: 20,
          nextSetId: 31,
          startedAt: "2026-06-21T19:00:00.000Z",
        }),
      ),
    ).toBe(true);
  });

  it("finds the next incomplete set and formats labels from prior completed work", () => {
    const activeView = view([
      lift(20, 1, [
        set(30, 1, "completed", { actualReps: 12, actualWeight: 240 }),
        set(31, 2, "active", { plannedWeight: 240 }),
      ]),
      lift(21, 2, [set(32, 1, "active")]),
    ]);

    expect(findNextIncompleteRestTimerTarget(activeView)).toEqual(
      expect.objectContaining({
        liftId: 20,
        setId: 31,
        label: "Set 2 \u2022 12 \u00d7 240",
        shortLabel: "Set 2",
      }),
    );
    expect(findRestTimerTargetBySetId(activeView, 31)?.label).toBe("Set 2 \u2022 12 \u00d7 240");
    expect(findRestTimerTargetBySetId(activeView, 30)).toBeNull();
  });

  it("detects completed and undone set transitions", () => {
    const before = view([lift(20, 1, [set(30, 1, "active")])]);
    const afterComplete = view([lift(20, 1, [set(30, 1, "completed", { actualReps: 10, actualWeight: 100 })])]);
    const afterUndo = view([lift(20, 1, [set(30, 1, "active", { actualWeight: 100 })])]);

    expect(didAnySetBecomeComplete(before, afterComplete)).toBe(true);
    expect(didAnySetBecomeIncomplete(afterComplete, afterUndo)).toBe(true);
  });
});

function view(lifts: ActiveWorkoutLiftView[]): ActiveWorkoutView {
  const countableSets = lifts.flatMap((lift) => lift.sets).filter((item) => item.status !== "skipped");
  const completedSets = countableSets.filter((item) => item.status === "completed").length;

  return {
    program: program(),
    workout: workout(),
    weekWorkouts: [],
    previousWorkoutId: null,
    nextWorkoutId: null,
    completedSets,
    totalSets: countableSets.length,
    canFinish: false,
    isReadOnly: false,
    lifts,
  };
}

function program(): Program {
  return {
    id: 1,
    name: "Back In Action",
    programLengthWeeks: 4,
    status: "active",
    locked: false,
    templateId: 1,
    createdAt: "2026-06-21T19:00:00.000Z",
    updatedAt: "2026-06-21T19:00:00.000Z",
  };
}

function workout(): Workout {
  return {
    id: 10,
    order: 1,
    workoutDay: 1,
    programWeek: 1,
    hidden: false,
    locked: false,
    status: "active",
    programId: 1,
    createdAt: "2026-06-21T19:00:00.000Z",
    updatedAt: "2026-06-21T19:00:00.000Z",
  };
}

function lift(id: number, order: number, sets: ActiveWorkoutSetView[]): ActiveWorkoutLiftView {
  return {
    id,
    exerciseId: id,
    exerciseName: `Lift ${id}`,
    repsOnly: false,
    timeBased: false,
    order,
    status: sets.every((item) => item.status === "completed") ? "completed" : "active",
    locked: false,
    feedbackSubmitted: false,
    manualCheckinStatus: "none",
    manualCheckinSourceLiftId: null,
    manualCheckinSourcePain: null,
    sets,
  };
}

function set(
  id: number,
  order: number,
  status: ActiveWorkoutSetView["status"],
  values: Partial<Pick<ActiveWorkoutSetView, "actualReps" | "actualWeight" | "plannedReps" | "plannedWeight">> = {},
): ActiveWorkoutSetView {
  return {
    id,
    order,
    plannedReps: values.plannedReps ?? null,
    actualReps: values.actualReps ?? null,
    plannedWeight: values.plannedWeight ?? null,
    actualWeight: values.actualWeight ?? null,
    status,
    locked: false,
  };
}
