import type { ExerciseSummary, Muscle } from "./Exercise";

export interface ExerciseCatalogRepository {
  listMuscles(): Promise<Muscle[]>;
  listExerciseSummariesByIds(ids: number[]): Promise<ExerciseSummary[]>;
  searchExercises(query: string): Promise<ExerciseSummary[]>;
}
