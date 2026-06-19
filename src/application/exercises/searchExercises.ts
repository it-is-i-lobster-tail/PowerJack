import type { ExerciseCatalogRepository } from "../../domain/exercises/ExerciseCatalogRepository";

export async function searchExercises(query: string, repository: ExerciseCatalogRepository) {
  return repository.searchExercises(query.trim());
}
