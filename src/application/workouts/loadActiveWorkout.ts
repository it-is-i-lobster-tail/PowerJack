import type { WorkoutRepository } from "../../domain/workouts/WorkoutRepository";

export async function loadActiveWorkout(repository: WorkoutRepository) {
  return repository.loadActive();
}
