import type { AppStateRepository } from "../domain/app-state/AppStateRepository";
import type { TrainingAnalyticsRepository } from "../domain/analytics/TrainingAnalyticsRepository";
import type { ExerciseCatalogRepository } from "../domain/exercises/ExerciseCatalogRepository";
import type { ProgramRepository } from "../domain/programs/ProgramRepository";
import type { TemplateRepository } from "../domain/templates/TemplateRepository";
import type { WorkoutRepository } from "../domain/workouts/WorkoutRepository";
import type { AppRuntimeCache } from "./AppRuntimeCache";

export interface AppServices {
  mode: "sqlite" | "memory";
  cache: AppRuntimeCache;
  appState: AppStateRepository;
  exercises: ExerciseCatalogRepository;
  templates: TemplateRepository;
  programs: ProgramRepository;
  workouts: WorkoutRepository;
  analytics: TrainingAnalyticsRepository;
  resetForAgent(): Promise<void>;
}
