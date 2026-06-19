import type { EntityId } from "../../domain/ids";
import type { WorkoutRepository } from "../../domain/workouts/WorkoutRepository";

export async function loadWorkoutView(workoutId: EntityId, repository: WorkoutRepository) {
  return repository.loadWorkoutView(workoutId);
}
