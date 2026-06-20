import type { EntityId } from "../../domain/ids";
import type { WorkoutRepository } from "../../domain/workouts/WorkoutRepository";

export async function removeLastSetFromLift(
  input: { liftId: EntityId },
  repository: WorkoutRepository,
) {
  validateEntityId(input.liftId, "Lift");
  return repository.removeLastSetFromLift(input);
}

function validateEntityId(value: EntityId, label: string): void {
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${label} was not found.`);
  }
}
