import type { EntityId } from "../../domain/ids";
import type { WorkoutRepository } from "../../domain/workouts/WorkoutRepository";

export async function finishWorkout(workoutId: EntityId, repository: WorkoutRepository) {
  return repository.finishWorkout(workoutId);
}
