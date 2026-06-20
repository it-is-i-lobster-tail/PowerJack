import type { AppServices } from "../../app/AppServices";
import { openPowerJackDatabase } from "./openDatabase";
import { runMigrations } from "./runMigrations";
import { SqliteAppStateRepository } from "./repositories/SqliteAppStateRepository";
import { SqliteExerciseCatalogRepository } from "./repositories/SqliteExerciseCatalogRepository";
import { SqliteProgramRepository } from "./repositories/SqliteProgramRepository";
import { SqliteTemplateRepository } from "./repositories/SqliteTemplateRepository";
import { SqliteTrainingAnalyticsRepository } from "./repositories/SqliteTrainingAnalyticsRepository";
import { SqliteWorkoutRepository } from "./repositories/SqliteWorkoutRepository";
import { seedReferenceData } from "./seeds/seedReferenceData";

export async function createDatabaseBackedServices(): Promise<AppServices> {
  const db = await openPowerJackDatabase();
  await runMigrations(db);
  await seedReferenceData(db);

  const appState = new SqliteAppStateRepository(db);
  const templates = new SqliteTemplateRepository(db);
  const programs = new SqliteProgramRepository(db);
  const workouts = new SqliteWorkoutRepository(db);

  return {
    mode: "sqlite",
    appState,
    exercises: new SqliteExerciseCatalogRepository(db),
    templates,
    programs,
    workouts,
    analytics: new SqliteTrainingAnalyticsRepository(db),
    resetForAgent: async () => {
      await appState.resetForAgent();
      await programs.resetForAgent();
      await templates.resetForAgent();
    },
  };
}
