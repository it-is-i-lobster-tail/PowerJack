import { describe, expect, it } from "vitest";
import { buildReferenceCatalog } from "../../src/infrastructure/database/seeds/buildReferenceCatalog";
import {
  referenceEquipment,
  referenceExercises,
  referenceMuscles,
} from "../../src/infrastructure/database/seeds/referenceData";

function uniqueValues(values: readonly string[]) {
  return new Set(values);
}

describe("reference seed data", () => {
  it("has stable deterministic snapshots", () => {
    expect(buildReferenceCatalog()).toEqual(buildReferenceCatalog());
  });

  it("keeps muscle, equipment, and exercise names unique for idempotent inserts", () => {
    const muscleNames = [...referenceMuscles];
    const equipmentNames = referenceEquipment.map((equipment) => equipment.name);
    const exerciseNames = referenceExercises.map((exercise) => exercise.name);

    expect(uniqueValues(muscleNames).size).toBe(muscleNames.length);
    expect(uniqueValues(equipmentNames).size).toBe(equipmentNames.length);
    expect(uniqueValues(exerciseNames).size).toBe(exerciseNames.length);
  });

  it("uses the extracted canonical muscle and equipment sets", () => {
    expect([...referenceMuscles]).toEqual([
      "Back",
      "Biceps",
      "Calves",
      "Chest",
      "Core",
      "Forearms",
      "Glutes",
      "Hamstrings",
      "Quads",
      "Shoulders",
      "Triceps",
    ]);
    expect(referenceEquipment.map((equipment) => equipment.name)).toEqual([
      "Barbell",
      "Bodyweight",
      "Cable",
      "Dumbbell",
      "Leg Press",
      "Machine",
      "Smith Machine",
      "Landmine",
      "EZ Bar",
      "Trap Bar",
      "Sled",
      "Kettlebell",
    ]);
  });

  it("uses the no-duplicate 201-exercise catalog", () => {
    const names = referenceExercises.map((exercise) => exercise.name);

    expect(names).toHaveLength(201);
    expect(names).toEqual(
      expect.arrayContaining([
        "Barbell Bench Press",
        "Barbell Back Squat",
        "Barbell Conventional Deadlift",
        "Pull-Up",
        "Barbell Bent-Over Row",
        "Barbell Overhead Press",
        "Cable Triceps Pushdown",
        "Dumbbell Walking Lunge",
        "Machine Seated Leg Curl",
        "Machine Calf Raise",
        "Weighted Dip",
        "Smith Machine Bench Press",
        "Landmine Row",
        "EZ Bar Curl",
        "Trap Bar Deadlift",
        "Sled Push",
        "Kettlebell Swing",
      ]),
    );
  });

  it("skips noisy imports, exact duplicates, and movement-intent aliases", () => {
    const names = referenceExercises.map((exercise) => exercise.name);

    expect(names).not.toEqual(
      expect.arrayContaining([
        "Pec Deck",
        "Pendlay Row",
        "Cable Seated Row",
        "Machine Lat Pulldown",
        "Reverse Pec Deck",
        "Barbell Deadlift",
        "Chest Dip",
        "Bench Dip",
        "Smith Machine Squat",
        "Back Extension",
        "EZ-Bar Curl",
        "EZ-Bar Skull Crusher",
        "45-Degree Leg Press",
        "Horizontal Leg Press",
        "Cable Pallof Press",
        "Weighted Plank",
        "Machine Neck Extension",
        "Machine Neck Flexion",
      ]),
    );
  });

  it("keeps conflict rows on existing canonical movement intent", () => {
    expect(referenceExercises.find((exercise) => exercise.name === "Barbell Shrug")).toMatchObject({
      primaryMuscle: "Back",
      equipment: "Barbell",
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Dumbbell Shrug")).toMatchObject({
      primaryMuscle: "Back",
      equipment: "Dumbbell",
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Cable Kickback")).toMatchObject({
      primaryMuscle: "Triceps",
      equipment: "Cable",
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Cable Glute Kickback")).toMatchObject({
      primaryMuscle: "Glutes",
      equipment: "Cable",
    });
  });

  it("does not reference missing muscles or equipment", () => {
    const muscles = new Set<string>(referenceMuscles);
    const equipment = new Set(referenceEquipment.map((item) => item.name));

    for (const exercise of referenceExercises) {
      expect(muscles.has(exercise.primaryMuscle), exercise.name).toBe(true);
      expect(equipment.has(exercise.equipment), exercise.name).toBe(true);

      for (const secondaryMuscle of exercise.secondaryMuscles) {
        expect(muscles.has(secondaryMuscle), exercise.name).toBe(true);
      }
    }
  });

  it("keeps representative rep ranges from the provided CSV", () => {
    expect(referenceExercises.find((exercise) => exercise.name === "Barbell Push Press")).toMatchObject({
      minRepsHypertrophy: 4,
      maxRepsHypertrophy: 8,
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Dumbbell Lateral Raise")).toMatchObject({
      minRepsHypertrophy: 8,
      maxRepsHypertrophy: 20,
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Cable Face Pull")).toMatchObject({
      minRepsHypertrophy: 12,
      maxRepsHypertrophy: 25,
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Weighted Pull-Up")).toMatchObject({
      minRepsHypertrophy: 4,
      maxRepsHypertrophy: 10,
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Smith Machine Back Squat")).toMatchObject({
      primaryMuscle: "Quads",
      equipment: "Smith Machine",
      minRepsHypertrophy: 6,
      maxRepsHypertrophy: 12,
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Trap Bar Deadlift")).toMatchObject({
      primaryMuscle: "Quads",
      equipment: "Trap Bar",
      minRepsHypertrophy: 4,
      maxRepsHypertrophy: 8,
    });
    expect(referenceExercises.find((exercise) => exercise.name === "Nordic Hamstring Curl")).toMatchObject({
      primaryMuscle: "Hamstrings",
      equipment: "Bodyweight",
      minRepsHypertrophy: 6,
      maxRepsHypertrophy: 12,
    });
  });
});
