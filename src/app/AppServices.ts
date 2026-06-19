import type { AppStateRepository } from "../domain/app-state/AppStateRepository";
import type { ExerciseCatalogRepository } from "../domain/exercises/ExerciseCatalogRepository";
import type { ProgramRepository } from "../domain/programs/ProgramRepository";
import type { TemplateRepository } from "../domain/templates/TemplateRepository";
import type { WorkoutRepository } from "../domain/workouts/WorkoutRepository";

export interface AppServices {
  mode: "sqlite" | "memory";
  appState: AppStateRepository;
  exercises: ExerciseCatalogRepository;
  templates: TemplateRepository;
  programs: ProgramRepository;
  workouts: WorkoutRepository;
  resetForAgent(): Promise<void>;
}
