import initSqlJs from "sql.js";
import { describe, expect, it } from "vitest";
import type { DatabaseClient } from "../../src/infrastructure/database/DatabaseClient";
import { databaseMigrations } from "../../src/infrastructure/database/migrations";
import { runMigrations } from "../../src/infrastructure/database/runMigrations";

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

  query<TRecord extends Record<string, unknown>>(
    sql: string,
    values: unknown[] = [],
  ): Promise<TRecord[]> {
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

describe("completed status enum migration", () => {
  it("converts old complete statuses, tightens checks, and preserves indexes", async () => {
    const SQL = await initSqlJs();
    const client = new SqlJsTestDatabaseClient(new SQL.Database());

    await runMigrationsThrough(client, 8);
    await insertOldCompleteRows(client);

    await runMigrations(client);

    await expect(tableStatuses(client, "programs")).resolves.toEqual(["completed"]);
    await expect(tableStatuses(client, "workouts")).resolves.toEqual(["completed"]);
    await expect(tableStatuses(client, "lifts")).resolves.toEqual(["completed"]);
    await expect(tableStatuses(client, "workout_sets")).resolves.toEqual(["completed"]);
    await expect(
      client.query("SELECT manual_checkin_status, manual_checkin_source_lift_id FROM lifts WHERE id = 1"),
    ).resolves.toEqual([{ manual_checkin_status: "pending", manual_checkin_source_lift_id: null }]);
    await expect(client.query("SELECT level_of_pain, level_of_effort, lift_id FROM feedback")).resolves.toEqual([
      { level_of_pain: 2, level_of_effort: 7, lift_id: 1 },
    ]);
    await expect(
      client.query(
        "SELECT active_program_id, active_workout_id, active_lift_id, rest_timer_state, rest_timer_next_set_id FROM app_state WHERE id = 1",
      ),
    ).resolves.toEqual([
      {
        active_program_id: 1,
        active_workout_id: 1,
        active_lift_id: 1,
        rest_timer_state: "running",
        rest_timer_next_set_id: 1,
      },
    ]);
    await expect(client.query("PRAGMA foreign_key_check")).resolves.toEqual([]);
    await expect(indexNames(client)).resolves.toEqual([
      "idx_lifts_workout_order",
      "idx_workout_sets_lift_order",
      "idx_workouts_program_status",
    ]);

    for (const table of ["programs", "workouts", "lifts", "workout_sets"]) {
      await expect(client.run(`UPDATE ${table} SET status = 'complete' WHERE id = 1`)).rejects.toThrow();
      await expect(client.run(`UPDATE ${table} SET status = 'completed' WHERE id = 1`)).resolves.toBeUndefined();
    }
  });
});

async function runMigrationsThrough(client: DatabaseClient, maxId: number): Promise<void> {
  await client.execute(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
  `);

  for (const migration of databaseMigrations.filter((item) => item.id <= maxId)) {
    await client.execute(migration.sql);
    await client.run("INSERT INTO schema_migrations (id, name) VALUES (?, ?)", [
      migration.id,
      migration.name,
    ]);
  }
}

async function insertOldCompleteRows(client: DatabaseClient): Promise<void> {
  await client.run("INSERT INTO muscles (id, name) VALUES (1, ?)", ["Chest"]);
  await client.run("INSERT INTO equipment (id, name) VALUES (1, ?)", ["Barbell"]);
  await client.run(
    "INSERT INTO exercises (id, name, primary_muscle_id, equipment_id, min_reps_hypertrophy, max_reps_hypertrophy) VALUES (1, ?, 1, 1, 8, 12)",
    ["Bench Press"],
  );
  await client.run("INSERT INTO templates (id, name, workouts_per_week) VALUES (1, ?, 1)", ["Push"]);
  await client.run(
    "INSERT INTO programs (id, name, program_length_weeks, status, locked, template_id) VALUES (1, ?, 4, 'complete', 1, 1)",
    ["Push x1"],
  );
  await client.run(
    'INSERT INTO workouts (id, "order", workout_day, program_week, hidden, locked, status, program_id) VALUES (1, 1, 1, 1, 0, 1, \'complete\', 1)',
  );
  await client.run(
    'INSERT INTO lifts (id, exercise_id, workout_id, locked, hidden, "order", status, planned, manual_checkin_status) VALUES (1, 1, 1, 1, 0, 1, \'complete\', 0, \'pending\')',
  );
  await client.run(
    'INSERT INTO workout_sets (id, planned_reps, actual_reps, planned_weight, actual_weight, "order", lift_id, locked, hidden, status, planned) VALUES (1, 10, 10, 135, 135, 1, 1, 1, 0, \'complete\', 0)',
  );
  await client.run("INSERT INTO feedback (id, level_of_pain, level_of_effort, lift_id) VALUES (1, 2, 7, 1)");
  await client.run(
    "INSERT INTO app_state (id, active_program_id, active_workout_id, active_lift_id, rest_timer_state, rest_timer_workout_id, rest_timer_lift_id, rest_timer_next_set_id, rest_timer_started_at, rest_timer_remaining_seconds) VALUES (1, 1, 1, 1, 'running', 1, 1, 1, '2026-06-23T12:00:00.000Z', 60)",
  );
}

async function tableStatuses(client: DatabaseClient, table: string): Promise<string[]> {
  const rows = await client.query<{ status: string }>(`SELECT status FROM ${table} ORDER BY id`);
  return rows.map((row) => row.status);
}

async function indexNames(client: DatabaseClient): Promise<string[]> {
  const rows = await client.query<{ name: string }>(`
    SELECT name
    FROM sqlite_master
    WHERE type = 'index'
      AND name IN ('idx_workouts_program_status', 'idx_lifts_workout_order', 'idx_workout_sets_lift_order')
    ORDER BY name
  `);

  return rows.map((row) => row.name);
}
