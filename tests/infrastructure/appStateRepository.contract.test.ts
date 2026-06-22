import { describe, expect, it } from "vitest";
import { createInMemoryAppServices } from "../../src/infrastructure/database/repositories/InMemoryRepositories";

describe("AppStateRepository contract", () => {
  it("loads deterministic empty startup state", async () => {
    const services = createInMemoryAppServices();

    await expect(services.appState.load()).resolves.toMatchObject({
      id: 1,
      activeProgramId: null,
      activeWorkoutId: null,
      activeLiftId: null,
    });
  });

  it("supports agent reset without deleting reference services", async () => {
    const services = createInMemoryAppServices();

    await services.resetForAgent();

    await expect(services.appState.load()).resolves.toMatchObject({
      activeProgramId: null,
      activeWorkoutId: null,
      activeLiftId: null,
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
