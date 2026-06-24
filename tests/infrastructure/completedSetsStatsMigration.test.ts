import { describe, expect, it } from "vitest";
import type { DatabaseClient } from "../../src/infrastructure/database/DatabaseClient";
import { runMigrations } from "../../src/infrastructure/database/runMigrations";
import { createSqlJsTestDatabaseClient } from "./sqlJsTestClient";

interface TableInfoRow extends Record<string, unknown> {
  name: string;
  type: string;
  notnull: number;
  dflt_value: string | null;
  pk: number;
}

interface IndexRow extends Record<string, unknown> {
  name: string;
}

describe("completed_sets_stats migration", () => {
  it("creates a constrained long-view stats table for completed workout sets", async () => {
    const client = await createSqlJsTestDatabaseClient();

    await runMigrations(client);
    await insertCompletedSetDependencies(client);

    const columns = await client.query<TableInfoRow>("PRAGMA table_info(completed_sets_stats)");

    expect(columns.map((column) => column.name)).toEqual([
      "created_at",
      "program_id",
      "set_id",
      "chest",
      "back",
      "biceps",
      "triceps",
      "shoulders",
      "core",
      "quads",
      "hamstrings",
      "glutes",
      "calves",
      "forearms",
    ]);
    expect(columns.find((column) => column.name === "set_id")).toMatchObject({
      type: "INTEGER",
      pk: 1,
    });
    expect(columns.find((column) => column.name === "created_at")).toMatchObject({
      notnull: 1,
      dflt_value: "CURRENT_TIMESTAMP",
    });

    await expect(indexNames(client)).resolves.toEqual([
      "idx_completed_sets_stats_created_at",
      "idx_completed_sets_stats_program_created_at",
    ]);

    await client.run(
      "INSERT INTO completed_sets_stats (program_id, set_id, chest, triceps, shoulders) VALUES (1, 1, 1, 0.5, 0.5)",
    );
    await expect(
      client.run("INSERT INTO completed_sets_stats (program_id, set_id, chest) VALUES (1, 1, 1)"),
    ).rejects.toThrow();
    await expect(
      client.run("INSERT INTO completed_sets_stats (program_id, set_id) VALUES (1, 2)"),
    ).rejects.toThrow();
    await expect(
      client.run("INSERT INTO completed_sets_stats (program_id, set_id, chest) VALUES (1, 3, 0.25)"),
    ).rejects.toThrow();
    await expect(client.query("PRAGMA foreign_key_check")).resolves.toEqual([]);
  });
});

async function insertCompletedSetDependencies(client: DatabaseClient): Promise<void> {
  await client.run("INSERT INTO muscles (id, name) VALUES (1, ?)", ["Chest"]);
  await client.run("INSERT INTO equipment (id, name) VALUES (1, ?)", ["Barbell"]);
  await client.run(
    "INSERT INTO exercises (id, name, primary_muscle_id, equipment_id, min_reps_hypertrophy, max_reps_hypertrophy) VALUES (1, ?, 1, 1, 8, 12)",
    ["Bench Press"],
  );
  await client.run("INSERT INTO templates (id, name, workouts_per_week) VALUES (1, ?, 1)", ["Push"]);
  await client.run(
    "INSERT INTO programs (id, name, program_length_weeks, status, locked, template_id) VALUES (1, ?, 4, 'active', 0, 1)",
    ["Push x1"],
  );
  await client.run(
    'INSERT INTO workouts (id, "order", workout_day, program_week, hidden, locked, status, program_id) VALUES (1, 1, 1, 1, 0, 0, \'active\', 1)',
  );
  await client.run(
    'INSERT INTO lifts (id, exercise_id, workout_id, locked, hidden, "order", status, planned) VALUES (1, 1, 1, 0, 0, 1, \'active\', 1)',
  );

  for (const setId of [1, 2, 3]) {
    await client.run(
      'INSERT INTO workout_sets (id, planned_reps, actual_reps, planned_weight, actual_weight, "order", lift_id, locked, hidden, status, planned) VALUES (?, NULL, 10, NULL, 135, ?, 1, 0, 0, \'completed\', 1)',
      [setId, setId],
    );
  }
}

async function indexNames(client: DatabaseClient): Promise<string[]> {
  const rows = await client.query<IndexRow>(`
    SELECT name
    FROM sqlite_master
    WHERE type = 'index'
      AND name IN (
        'idx_completed_sets_stats_created_at',
        'idx_completed_sets_stats_program_created_at'
      )
    ORDER BY name
  `);

  return rows.map((row) => row.name);
}
