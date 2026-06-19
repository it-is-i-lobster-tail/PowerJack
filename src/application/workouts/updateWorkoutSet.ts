import type { EntityId } from "../../domain/ids";
import type { WorkoutRepository } from "../../domain/workouts/WorkoutRepository";

export async function updateWorkoutSet(
  input: {
    setId: EntityId;
    actualReps: number | null;
    actualWeight: number | null;
  },
  repository: WorkoutRepository,
) {
  validateNullablePositiveInteger(input.actualReps, "Reps");
  validateNullablePositiveInteger(input.actualWeight, "Weight");

  return repository.updateSetActuals(input);
}

function validateNullablePositiveInteger(value: number | null, label: string): void {
  if (value === null) {
    return;
  }

  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${label} must be a non-zero integer.`);
  }
}
