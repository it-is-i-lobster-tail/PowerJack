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
      expect.arrayContaining([expect.objectContaining({ name: "Weighted Pull-Up" })]),
    );
    await expect(services.exercises.searchExercises("triceps")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Cable Triceps Pushdown" })]),
    );
    await expect(services.exercises.searchExercises("smith")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Smith Machine Bench Press" })]),
    );
    await expect(services.exercises.searchExercises("landmine")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Landmine Row" })]),
    );
    await expect(services.exercises.searchExercises("trap bar")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Trap Bar Deadlift" })]),
    );
    await expect(services.exercises.searchExercises("kettlebell")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Kettlebell Swing" })]),
    );
    await expect(services.exercises.searchExercises("sled")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Sled Push" })]),
    );
    await expect(services.exercises.searchExercises("tibialis")).resolves.toEqual(
      expect.arrayContaining([expect.objectContaining({ name: "Machine Tibialis Raise" })]),
    );
  });
});
