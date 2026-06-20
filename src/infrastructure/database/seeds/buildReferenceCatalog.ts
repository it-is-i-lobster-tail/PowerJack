import type { Equipment, ExerciseSummary, Muscle } from "../../../domain/exercises/Exercise";
import { referenceEquipment, referenceExercises, referenceMuscles } from "./referenceData";

export interface ReferenceCatalogSnapshot {
  muscles: Muscle[];
  equipment: Equipment[];
  exercises: ExerciseSummary[];
}

const now = "2026-06-18T00:00:00.000Z";

export function buildReferenceCatalog(): ReferenceCatalogSnapshot {
  const muscles = referenceMuscles.map<Muscle>((name, index) => ({
    id: index + 1,
    name,
    createdAt: now,
    updatedAt: now,
  }));
  const equipment = referenceEquipment.map<Equipment>((item, index) => ({
    id: index + 1,
    name: item.name,
    weightOverloadable: item.weightOverloadable,
    repOverloadable: item.repOverloadable,
    timeOverloadable: item.timeOverloadable,
  }));

  const exercises = referenceExercises.map<ExerciseSummary>((exercise, index) => ({
    id: index + 1,
    name: exercise.name,
    primaryMuscleName: exercise.primaryMuscle,
    secondaryMuscleNames: exercise.secondaryMuscles,
    equipmentName: exercise.equipment,
    repsOnly: exercise.repsOnly,
    minRepsHypertrophy: exercise.minRepsHypertrophy,
    maxRepsHypertrophy: exercise.maxRepsHypertrophy,
  }));

  return { muscles, equipment, exercises };
}
