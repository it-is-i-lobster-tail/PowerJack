import type { ExerciseCatalogRepository } from "../../domain/exercises/ExerciseCatalogRepository";

export async function listExerciseSummariesByIds(ids: number[], repository: ExerciseCatalogRepository) {
  return repository.listExerciseSummariesByIds(ids);
}
