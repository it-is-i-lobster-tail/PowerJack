import type { ExerciseCatalogRepository } from "../../domain/exercises/ExerciseCatalogRepository";

export async function listMuscles(repository: ExerciseCatalogRepository) {
  return repository.listMuscles();
}
