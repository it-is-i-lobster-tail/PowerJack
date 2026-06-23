import { describe, expect, it } from "vitest";
import { startProgramFromTemplate } from "../../src/application/programs/startProgramFromTemplate";
import { saveTemplate } from "../../src/application/templates/saveTemplate";
import { addSetToLift } from "../../src/application/workouts/addSetToLift";
import { removeLastSetFromLift } from "../../src/application/workouts/removeLastSetFromLift";
import { updateWorkoutSet } from "../../src/application/workouts/updateWorkoutSet";
import type { AppServices } from "../../src/app/AppServices";
import type { CompletedSetEvent } from "../../src/domain/analytics/TrainingAnalytics";
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
import { createSqlJsTestDatabaseClient } from "./sqlJsTestClient";

interface CompletedSetStatsRow extends Record<string, unknown> {
  created_at: string;
  program_id: number;
  set_id: number;
  chest: number;
  back: number;
  biceps: number;
  triceps: number;
  shoulders: number;
  core: number;
  quads: number;
  hamstrings: number;
  glutes: number;
  calves: number;
  forearms: number;
}

describe("completed_sets_stats SQLite repository integration", () => {
  it("materializes one live stats row per completed set", async () => {
    const { client, services } = await createSqliteServices();
    const benchPressId = await findExerciseId(services, "Barbell Bench Press");
    const template = await createTemplate(services, [[benchPressId]]);

    await startTemplateProgram(services, template.id);

    let view = await loadRequiredActiveWorkout(services);
    const lift = view.lifts[0];
    const firstSet = lift?.sets[0];

    if (!lift || !firstSet) {
      throw new Error("Expected bench press lift and first set.");
    }

    view = await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 10, actualWeight: 135 },
      services.workouts,
    );

    let statsRows = await loadCompletedSetStatsRows(client);
    const firstStatsRow = statsRows[0];

    expect(statsRows).toHaveLength(1);
    expect(firstStatsRow).toMatchObject({
      back: 0,
      biceps: 0,
      calves: 0,
      chest: 1,
      core: 0,
      forearms: 0,
      glutes: 0,
      hamstrings: 0,
      program_id: view.program.id,
      quads: 0,
      set_id: firstSet.id,
      shoulders: 0.5,
      triceps: 0.5,
    });

    if (!firstStatsRow) {
      throw new Error("Expected completed set stats row.");
    }

    const firstCreatedAt = firstStatsRow.created_at;

    await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 9, actualWeight: 145 },
      services.workouts,
    );
    statsRows = await loadCompletedSetStatsRows(client);

    expect(statsRows).toHaveLength(1);
    expect(statsRows[0]?.created_at).toBe(firstCreatedAt);

    await updateWorkoutSet(
      { setId: firstSet.id, actualReps: null, actualWeight: 145 },
      services.workouts,
    );

    await expect(loadCompletedSetStatsRows(client)).resolves.toEqual([]);

    await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 8, actualWeight: 145 },
      services.workouts,
    );

    expect(await loadCompletedSetStatsRows(client)).toHaveLength(1);

    view = await addSetToLift({ liftId: lift.id }, services.workouts);

    const addedSet = view.lifts[0]?.sets.find((set) => set.order === 3);

    if (!addedSet) {
      throw new Error("Expected added manual set.");
    }

    await updateWorkoutSet(
      { setId: addedSet.id, actualReps: 7, actualWeight: 145 },
      services.workouts,
    );
    await expect(loadCompletedSetStatsRowsForSet(client, addedSet.id)).resolves.toHaveLength(1);

    await removeLastSetFromLift({ liftId: lift.id }, services.workouts);

    await expect(loadCompletedSetStatsRowsForSet(client, addedSet.id)).resolves.toEqual([]);
    await expect(loadCompletedSetStatsRows(client)).resolves.toHaveLength(1);
  });

  it("loads credited muscle events from completed set stats rows", async () => {
    const { services } = await createSqliteServices();
    const benchPressId = await findExerciseId(services, "Barbell Bench Press");
    const template = await createTemplate(services, [[benchPressId]]);

    await startTemplateProgram(services, template.id);

    let view = await loadRequiredActiveWorkout(services);
    const firstSet = view.lifts[0]?.sets[0];
    const secondSet = view.lifts[0]?.sets[1];

    if (!firstSet || !secondSet) {
      throw new Error("Expected two bench press sets.");
    }

    await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 10, actualWeight: 135 },
      services.workouts,
    );
    view = await updateWorkoutSet(
      { setId: secondSet.id, actualReps: 8, actualWeight: 135 },
      services.workouts,
    );

    const rangeEvents = await services.analytics.loadCompletedSetEvents({
      fromInclusive: "2000-01-01T00:00:00.000Z",
      toExclusive: "2100-01-01T00:00:00.000Z",
    });
    const programEvents = await services.analytics.loadCompletedSetEventsForProgram(view.program.id);
    const outOfRangeEvents = await services.analytics.loadCompletedSetEvents({
      fromInclusive: "1900-01-01T00:00:00.000Z",
      toExclusive: "1901-01-01T00:00:00.000Z",
    });

    expect(rangeEvents).toHaveLength(6);
    expect(programEvents).toHaveLength(6);
    expect(outOfRangeEvents).toEqual([]);
    expect(sumSetCredits(rangeEvents, "Chest")).toBe(2);
    expect(sumSetCredits(rangeEvents, "Triceps")).toBe(1);
    expect(sumSetCredits(rangeEvents, "Shoulders")).toBe(1);
    expect(sumSetCredits(programEvents, "Chest")).toBe(2);
    expect(sumSetCredits(programEvents, "Triceps")).toBe(1);
    expect(sumSetCredits(programEvents, "Shoulders")).toBe(1);
  });
});

async function createSqliteServices(): Promise<{
  client: DatabaseClient;
  services: AppServices;
}> {
  const client = await createSqlJsTestDatabaseClient();

  await runMigrations(client);
  await seedReferenceData(client);

  const appState = new SqliteAppStateRepository(client);
  const templates = new SqliteTemplateRepository(client);
  const programs = new SqliteProgramRepository(client);
  const workouts = new SqliteWorkoutRepository(client);

  return {
    client,
    services: {
      mode: "sqlite",
      appState,
      exercises: new SqliteExerciseCatalogRepository(client),
      templates,
      programs,
      workouts,
      analytics: new SqliteTrainingAnalyticsRepository(client),
      resetForAgent: () => Promise.resolve(),
    },
  };
}

async function createTemplate(services: AppServices, exerciseIdsByDay: number[][]) {
  return saveTemplate(
    {
      name: "Stats Test",
      focusMuscleIds: [1],
      workoutsPerWeek: exerciseIdsByDay.length,
      days: exerciseIdsByDay.map((exerciseIds, index) => ({
        exerciseIds,
        order: index + 1,
      })),
    },
    services.templates,
  );
}

async function startTemplateProgram(services: AppServices, templateId: number): Promise<void> {
  await startProgramFromTemplate(
    { templateId, programLengthWeeks: 4 },
    {
      appState: services.appState,
      programs: services.programs,
      templates: services.templates,
    },
  );
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

async function loadCompletedSetStatsRows(client: DatabaseClient): Promise<CompletedSetStatsRow[]> {
  return client.query<CompletedSetStatsRow>("SELECT * FROM completed_sets_stats ORDER BY set_id ASC");
}

async function loadCompletedSetStatsRowsForSet(
  client: DatabaseClient,
  setId: number,
): Promise<CompletedSetStatsRow[]> {
  return client.query<CompletedSetStatsRow>(
    "SELECT * FROM completed_sets_stats WHERE set_id = ? ORDER BY set_id ASC",
    [setId],
  );
}

function sumSetCredits(events: CompletedSetEvent[], muscleName: string): number {
  return events
    .filter((event) => event.muscleName === muscleName)
    .reduce((total, event) => total + event.setCredit, 0);
}
