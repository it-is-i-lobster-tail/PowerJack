import type { EntityId } from "../../domain/ids";
import type { WorkoutRepository } from "../../domain/workouts/WorkoutRepository";

export async function changeLiftExercise(
  input: { liftId: EntityId; exerciseId: EntityId },
  repository: WorkoutRepository,
) {
  validateEntityId(input.liftId, "Lift");
  validateEntityId(input.exerciseId, "Exercise");
  return repository.changeLiftExercise(input);
}

function validateEntityId(value: EntityId, label: string): void {
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${label} was not found.`);
  }
}
