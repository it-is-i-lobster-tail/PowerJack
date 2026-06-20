import { describe, expect, it } from "vitest";
import { mapExerciseSummaryRow } from "../../src/infrastructure/database/mappers/exerciseMapper";

describe("mapExerciseSummaryRow", () => {
  it("maps SQLite row names to domain names", () => {
    expect(
      mapExerciseSummaryRow({
        id: 1,
        name: "Barbell Bench Press",
        primary_muscle_name: "Chest",
        secondary_muscle_names: "Triceps,Shoulders",
        equipment_name: "Barbell",
        reps_only: 0,
        min_reps_hypertrophy: 6,
        max_reps_hypertrophy: 12,
      }),
    ).toEqual({
      id: 1,
      name: "Barbell Bench Press",
      primaryMuscleName: "Chest",
      secondaryMuscleNames: ["Triceps", "Shoulders"],
      equipmentName: "Barbell",
      repsOnly: false,
      minRepsHypertrophy: 6,
      maxRepsHypertrophy: 12,
    });
  });
});
