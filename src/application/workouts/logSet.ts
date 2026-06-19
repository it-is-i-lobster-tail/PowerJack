import type { WorkoutRepository } from "../../domain/workouts/WorkoutRepository";

export async function logSet(
  input: { setId: number; actualReps: number; actualWeight: number },
  repository: WorkoutRepository,
) {
  if (!Number.isInteger(input.actualReps) || input.actualReps <= 0) {
    throw new Error("Reps must be a non-zero integer.");
  }

  if (!Number.isInteger(input.actualWeight) || input.actualWeight <= 0) {
    throw new Error("Weight must be a non-zero integer.");
  }

  return repository.updateSetActuals(input);
}
