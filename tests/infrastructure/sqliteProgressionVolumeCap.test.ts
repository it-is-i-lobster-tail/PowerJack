import initSqlJs from "sql.js";
import { describe, expect, it } from "vitest";
import { startProgramFromTemplate } from "../../src/application/programs/startProgramFromTemplate";
import { saveTemplate } from "../../src/application/templates/saveTemplate";
import { addSetToLift } from "../../src/application/workouts/addSetToLift";
import { finishWorkout } from "../../src/application/workouts/finishWorkout";
import { submitLiftFeedback } from "../../src/application/workouts/submitLiftFeedback";
import { updateWorkoutSet } from "../../src/application/workouts/updateWorkoutSet";
import type { AppServices } from "../../src/app/AppServices";
import { AppRuntimeCache } from "../../src/app/AppRuntimeCache";
import type { ActiveWorkoutView } from "../../src/domain/workouts/Workout";
import type { DatabaseClient } from "../../src/infrastructure/database/DatabaseClient";
import { runMigrations } from "../../src/infrastructure/database/runMigrations";
import { SqliteAppStateRepository } from "../../src/infrastructure/database/repositories/SqliteAppStateRepository";
import { SqliteExerciseCatalogRepository } from "../../src/infrastructure/database/repositories/SqliteExerciseCatalogRepository";
import { SqliteProgramRepository } from "../../src/infrastructure/database/repositories/SqliteProgramRepository";
import { SqliteTemplateRepository } from "../../src/infrastructure/database/repositories/SqliteTemplateRepository";
import { SqliteTrainingAnalyticsRepository } from "../../src/infrastructure/database/repositories/SqliteTrainingAnalyticsRepository";
import { SqliteWorkoutRepository } from "../../src/infrastructure/database/repositories/SqliteWorkoutRepository";
import { seedReferenceData } from "../../src/infrastructure/database/seeds/seedReferenceData";

type SqlValue = string | number | Uint8Array | null;

interface SqlJsStatement {
  bind(values: SqlValue[]): void;
  free(): void;
  getAsObject(): Record<string, unknown>;
  step(): boolean;
}

interface SqlJsDatabase {
  prepare(sql: string): SqlJsStatement;
  run(sql: string, values?: SqlValue[]): void;
}

class SqlJsTestDatabaseClient implements DatabaseClient {
  constructor(private readonly db: SqlJsDatabase) {}

  execute(sql: string): Promise<void> {
    try {
      this.db.run(sql);
      return Promise.resolve();
    } catch (error) {
      return Promise.reject(toError(error));
    }
  }

  query<TRecord extends Record<string, unknown>>(sql: string, values: unknown[] = []): Promise<TRecord[]> {
    let statement: SqlJsStatement;

    try {
      statement = this.db.prepare(sql);
    } catch (error) {
      return Promise.reject(toError(error));
    }

    const rows: TRecord[] = [];

    try {
      statement.bind(values as SqlValue[]);

      while (statement.step()) {
        rows.push(statement.getAsObject() as TRecord);
      }
    } finally {
      statement.free();
    }

    return Promise.resolve(rows);
  }

  run(sql: string, values: unknown[] = []): Promise<void> {
    try {
      this.db.run(sql, values as SqlValue[]);
      return Promise.resolve();
    } catch (error) {
      return Promise.reject(toError(error));
    }
  }

  async transaction<TResult>(operation: (client: DatabaseClient) => Promise<TResult>): Promise<TResult> {
    return operation(this);
  }
}

function toError(error: unknown): Error {
  return error instanceof Error ? error : new Error(String(error));
}

describe("SQLite progression volume cap", () => {
  it("counts previous-week secondary muscle credit before adding focus volume", async () => {
    const services = await createSqliteTestServices();
    const chestId = await findMuscleId(services, "Chest");
    const exerciseIds = await Promise.all(
      [
        "Dumbbell Fly",
        "Barbell Skull Crusher",
        "Dumbbell Overhead Triceps Extension",
        "Dumbbell Skull Crusher",
        "Cable Overhead Triceps Extension",
        "EZ Bar Skull Crusher",
        "Barbell Skull Crusher",
        "Dumbbell Overhead Triceps Extension",
        "Dumbbell Skull Crusher",
        "Cable Overhead Triceps Extension",
        "EZ Bar Skull Crusher",
      ].map((name) => findExerciseId(services, name)),
    );
    const template = await saveTemplate(
      {
        name: "Shoulder Cap",
        focusMuscleIds: [chestId],
        workoutsPerWeek: 1,
        days: [{ order: 1, exerciseIds }],
      },
      services.templates,
    );

    await startProgramFromTemplate(
      { templateId: template.id, programLengthWeeks: 4 },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    let view = await loadRequiredActiveWorkout(services);
    view = await addSetsToLiftCounts(services, view, [2, 5, 5, 5, 5, 5, 5, 5, 5, 4, 4]);
    view = await submitFeedbackForCompletedLifts(
      services,
      await completeWorkout(services, view, [12, 10, 10, 10, 10], 100),
    );

    let weekTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!weekTwo) {
      throw new Error("Expected week 2.");
    }

    weekTwo = await submitFeedbackForCompletedLifts(
      services,
      await completeWorkout(services, weekTwo, [12, 10, 10, 10, 10], 100),
    );

    const weekThree = await finishWorkout(weekTwo.workout.id, services.workouts);

    if (!weekThree) {
      throw new Error("Expected week 3.");
    }

    expect(weekThree.lifts[0]?.sets).toEqual([
      expect.objectContaining({ order: 1, plannedReps: 13, plannedWeight: 100 }),
      expect.objectContaining({ order: 2, plannedReps: 11, plannedWeight: 100 }),
    ]);
  });
});

async function createSqliteTestServices(): Promise<AppServices> {
  const SQL = await initSqlJs();
  const client = new SqlJsTestDatabaseClient(new SQL.Database());

  await runMigrations(client);
  await seedReferenceData(client);

  const appState = new SqliteAppStateRepository(client);
  const templates = new SqliteTemplateRepository(client);
  const programs = new SqliteProgramRepository(client);
  const workouts = new SqliteWorkoutRepository(client);
  const cache = new AppRuntimeCache({ appState, templates, workouts });

  return {
    mode: "sqlite",
    cache,
    appState,
    exercises: new SqliteExerciseCatalogRepository(client),
    templates,
    programs,
    workouts,
    analytics: new SqliteTrainingAnalyticsRepository(client),
    resetForAgent: async () => {
      await appState.resetForAgent();
      await programs.resetForAgent();
      await templates.resetForAgent();
      await seedReferenceData(client);
      cache.clear();
    },
  };
}

async function findMuscleId(services: AppServices, name: string): Promise<number> {
  const muscles = await services.exercises.listMuscles();
  const muscle = muscles.find((item) => item.name === name);

  if (!muscle) {
    throw new Error(`Expected muscle ${name}.`);
  }

  return muscle.id;
}

async function findExerciseId(services: AppServices, name: string): Promise<number> {
  const exercises = await services.exercises.searchExercises(name);
  const exercise = exercises.find((item) => item.name === name);

  if (!exercise) {
    throw new Error(`Expected exercise ${name}.`);
  }

  return exercise.id;
}

async function loadRequiredActiveWorkout(services: AppServices): Promise<ActiveWorkoutView> {
  const view = await services.workouts.loadActive();

  if (!view) {
    throw new Error("Expected active workout.");
  }

  return view;
}

async function addSetsToLiftCounts(
  services: AppServices,
  view: ActiveWorkoutView,
  targetCounts: number[],
): Promise<ActiveWorkoutView> {
  let nextView = view;

  for (const [liftIndex, targetCount] of targetCounts.entries()) {
    while ((nextView.lifts[liftIndex]?.sets.length ?? 0) < targetCount) {
      const liftId = nextView.lifts[liftIndex]?.id;

      if (!liftId) {
        throw new Error(`Expected lift ${liftIndex + 1}.`);
      }

      nextView = await addSetToLift({ liftId }, services.workouts);
    }
  }

  return nextView;
}

async function completeWorkout(
  services: AppServices,
  view: ActiveWorkoutView,
  repsBySet: number[],
  weight: number,
): Promise<ActiveWorkoutView> {
  let nextView = view;

  for (const lift of view.lifts) {
    for (const set of lift.sets) {
      nextView = await updateWorkoutSet(
        {
          setId: set.id,
          actualReps: repsBySet[set.order - 1] ?? repsBySet[0] ?? 10,
          actualWeight: weight,
        },
        services.workouts,
      );
    }
  }

  return nextView;
}

async function submitFeedbackForCompletedLifts(
  services: AppServices,
  view: ActiveWorkoutView,
): Promise<ActiveWorkoutView> {
  let nextView = view;

  for (const lift of view.lifts.filter((lift) => lift.status === "completed" && !lift.feedbackSubmitted)) {
    nextView = await submitLiftFeedback(
      { liftId: lift.id, levelOfPain: 1, levelOfEffort: 3 },
      services.workouts,
    );
  }

  return nextView;
}
