import type { ExerciseSummary, Muscle } from "./Exercise";

export interface ExerciseCatalogRepository {
  listMuscles(): Promise<Muscle[]>;
  searchExercises(query: string): Promise<ExerciseSummary[]>;
}
