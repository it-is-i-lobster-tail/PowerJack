import { describe, expect, it } from "vitest";
import { createRunningRestTimer } from "../../src/domain/app-state/restTimer";
import { createInMemoryAppServices } from "../../src/infrastructure/database/repositories/InMemoryRepositories";

describe("AppStateRepository contract", () => {
  it("loads deterministic empty startup state", async () => {
    const services = createInMemoryAppServices();

    await expect(services.appState.load()).resolves.toMatchObject({
      id: 1,
      activeProgramId: null,
      activeWorkoutId: null,
      activeLiftId: null,
      restTimer: {
        state: "idle",
        workoutId: null,
        liftId: null,
        nextSetId: null,
        startedAt: null,
        durationSeconds: 120,
        remainingSeconds: 0,
      },
    });
  });

  it("persists rest timer state", async () => {
    const services = createInMemoryAppServices();
    const timer = createRunningRestTimer({
      workoutId: 10,
      liftId: 20,
      nextSetId: 30,
      startedAt: "2026-06-21T19:00:00.000Z",
    });

    await services.appState.saveRestTimer({ ...timer, remainingSeconds: 84 });

    await expect(services.appState.load()).resolves.toMatchObject({
      restTimer: {
        state: "running",
        workoutId: 10,
        liftId: 20,
        nextSetId: 30,
        startedAt: "2026-06-21T19:00:00.000Z",
        durationSeconds: 120,
        remainingSeconds: 84,
      },
    });
  });

  it("supports agent reset without deleting reference services", async () => {
    const services = createInMemoryAppServices();

    await services.resetForAgent();

    await expect(services.appState.load()).resolves.toMatchObject({
      activeProgramId: null,
      activeWorkoutId: null,
      activeLiftId: null,
      restTimer: {
        state: "idle",
        workoutId: null,
        liftId: null,
        nextSetId: null,
      },
    });
    await expect(services.exercises.searchExercises("bench")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Barbell Bench Press" })]),
    );
    await expect(services.exercises.searchExercises("squat")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Barbell Back Squat" })]),
    );
    await expect(services.exercises.searchExercises("pull-up")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Pull Up" })]),
    );
    await expect(services.exercises.searchExercises("pull up")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Weighted Pull Up" })]),
    );
    await expect(services.exercises.searchExercises("PUSH UP")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Push Up" })]),
    );
    await expect(services.exercises.searchExercises("triceps")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Cable Triceps Pushdown" })]),
    );
    await expect(services.exercises.searchExercises("smith")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Smith Machine Bench Press" })]),
    );
    await expect(services.exercises.searchExercises("lat pulldown")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Cable Lat Pulldown" })]),
    );
    await expect(services.exercises.searchExercises("trap bar")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Trap Bar Deadlift" })]),
    );
    await expect(services.exercises.searchExercises("ez bar")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "EZ Bar Curl" })]),
    );

    const legPress = (await services.exercises.searchExercises("leg press")).find((exercise) => exercise.name === "Leg Press");
    const trapBarDeadlift = (await services.exercises.searchExercises("trap bar")).find(
      (exercise) => exercise.name === "Trap Bar Deadlift",
    );

    expect(legPress).toBeDefined();
    expect(trapBarDeadlift).toBeDefined();

    if (!legPress || !trapBarDeadlift) {
      throw new Error("Expected reference exercises to exist.");
    }

    await expect(services.exercises.listExerciseSummariesByIds([trapBarDeadlift.id, legPress.id])).resolves.toEqual([
      expect.objectContaining({ name: "Trap Bar Deadlift" }),
      expect.objectContaining({ name: "Leg Press" }),
    ]);
  });
});
