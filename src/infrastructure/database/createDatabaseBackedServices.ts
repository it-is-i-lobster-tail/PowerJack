import type { AppServices } from "../../app/AppServices";
import { AppRuntimeCache } from "../../app/AppRuntimeCache";
import type { DatabaseClient } from "./DatabaseClient";
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
  await suspendPersistence(db, async () => {
    await runMigrations(db);
    await seedReferenceData(db);
  });

  const appState = new SqliteAppStateRepository(db);
  const templates = new SqliteTemplateRepository(db);
  const programs = new SqliteProgramRepository(db);
  const workouts = new SqliteWorkoutRepository(db);
  const cache = new AppRuntimeCache({ appState, templates, workouts });

  return {
    mode: "sqlite",
    cache,
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
      await suspendPersistence(db, async () => {
        await seedReferenceData(db);
      });
      await flushPendingWrites(db);
      cache.clear();
    },
  };
}

interface WebPersistenceControls {
  flushPendingWrites(): Promise<void>;
  suspendPersistence<TResult>(operation: () => Promise<TResult>): Promise<TResult>;
}

function hasWebPersistenceControls(db: DatabaseClient): db is DatabaseClient & WebPersistenceControls {
  const controls = db as Partial<WebPersistenceControls>;
  return typeof controls.flushPendingWrites === "function" && typeof controls.suspendPersistence === "function";
}

async function suspendPersistence<TResult>(
  db: DatabaseClient,
  operation: () => Promise<TResult>,
): Promise<TResult> {
  if (!hasWebPersistenceControls(db)) {
    return operation();
  }

  return db.suspendPersistence(operation);
}

async function flushPendingWrites(db: DatabaseClient): Promise<void> {
  if (hasWebPersistenceControls(db)) {
    await db.flushPendingWrites();
  }
}
