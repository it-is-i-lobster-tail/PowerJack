import type { AppState } from "../../../domain/app-state/AppState";
import type { ProgramRepository } from "../../../domain/programs/ProgramRepository";
import type { TemplateAggregate } from "../../../domain/templates/Template";
import type { DatabaseClient } from "../DatabaseClient";
import { mapAppStateRow, type AppStateRow } from "../mappers/appStateMapper";

interface CountRow extends Record<string, unknown> {
  count: number;
}

interface LastInsertIdRow extends Record<string, unknown> {
  id: number;
}

interface ActiveProgramRow extends Record<string, unknown> {
  active_program_id: number | null;
}

export class SqliteProgramRepository implements ProgramRepository {
  constructor(private readonly db: DatabaseClient) {}

  async startFromTemplate(input: {
    template: TemplateAggregate;
    programLengthWeeks: number;
    replaceActiveProgram?: boolean;
  }): Promise<AppState> {
    return this.db.transaction(async (client) => {
      const activeProgramRows = await client.query<ActiveProgramRow>(
        "SELECT active_program_id FROM app_state WHERE id = 1",
      );
      const activeProgramId = activeProgramRows[0]?.active_program_id ?? null;

      if (activeProgramId && !input.replaceActiveProgram) {
        throw new Error("An active program already exists.");
      }

      validateTemplateForProgramStart(input.template);

      if (activeProgramId && input.replaceActiveProgram) {
        await haltActiveProgram(client, activeProgramId);
      }

      const usageRows = await client.query<CountRow>(
        "SELECT COUNT(*) AS count FROM programs WHERE template_id = ?",
        [input.template.id],
      );
      const usageCount = (usageRows[0]?.count ?? 0) + 1;
      const programName = `${input.template.name} x${usageCount}`;

      await client.run(
        `
          INSERT INTO programs
            (name, program_length_weeks, status, locked, template_id, created_at, updated_at)
          VALUES (?, ?, 'active', 0, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `,
        [programName, input.programLengthWeeks, input.template.id],
      );

      const programId = await loadLastInsertId(client);
      let activeWorkoutId: number | null = null;
      let activeLiftId: number | null = null;

      for (const day of input.template.days) {
        const isActiveDay = day.order === 1;
        const status = isActiveDay ? "active" : "planned";
        const locked = isActiveDay ? 0 : 1;

        await client.run(
          `
            INSERT INTO workouts
              ("order", workout_day, program_week, hidden, locked, status, program_id, created_at, updated_at)
            VALUES (?, ?, 1, 0, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          `,
          [day.order, day.order, locked, status, programId],
        );

        const workoutId = await loadLastInsertId(client);

        if (isActiveDay) {
          activeWorkoutId = workoutId;
        }

        for (const [exerciseIndex, exerciseId] of day.exerciseIds.entries()) {
          await client.run(
            `
              INSERT INTO lifts
                (exercise_id, workout_id, locked, hidden, "order", status, planned, created_at, updated_at)
              VALUES (?, ?, ?, 0, ?, ?, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            `,
            [exerciseId, workoutId, locked, exerciseIndex + 1, status],
          );

          const liftId = await loadLastInsertId(client);

          if (isActiveDay && activeLiftId === null) {
            activeLiftId = liftId;
          }

          for (let setOrder = 1; setOrder <= 2; setOrder += 1) {
            await client.run(
              `
                INSERT INTO workout_sets
                  (
                    planned_reps,
                    actual_reps,
                    planned_weight,
                    actual_weight,
                    "order",
                    lift_id,
                    locked,
                    hidden,
                    status,
                    planned,
                    created_at,
                    updated_at
                  )
                VALUES (NULL, NULL, NULL, NULL, ?, ?, ?, 0, ?, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
              `,
              [setOrder, liftId, locked, status],
            );
          }
        }
      }

      if (!activeWorkoutId || !activeLiftId) {
        throw new Error("Template did not create an active workout.");
      }

      await client.run(
        `
          UPDATE app_state
          SET
            active_program_id = ?,
            active_workout_id = ?,
            active_lift_id = ?,
            updated_at = CURRENT_TIMESTAMP
          WHERE id = 1
        `,
        [programId, activeWorkoutId, activeLiftId],
      );

      const appStateRows = await client.query<AppStateRow>("SELECT * FROM app_state WHERE id = 1");

      if (!appStateRows[0]) {
        throw new Error("App state could not be loaded after program start.");
      }

      return mapAppStateRow(appStateRows[0]);
    });
  }

  async resetForAgent(): Promise<void> {
    await this.db.run("DELETE FROM programs");
  }
}

async function haltActiveProgram(client: DatabaseClient, programId: number): Promise<void> {
  await client.run(
    `
      UPDATE programs
      SET status = 'halted', locked = 1, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `,
    [programId],
  );
  await client.run(
    `
      UPDATE workouts
      SET status = 'halted', locked = 1, updated_at = CURRENT_TIMESTAMP
      WHERE program_id = ?
    `,
    [programId],
  );
  await client.run(
    `
      UPDATE lifts
      SET status = 'halted', locked = 1, updated_at = CURRENT_TIMESTAMP
      WHERE workout_id IN (
        SELECT id
        FROM workouts
        WHERE program_id = ?
      )
    `,
    [programId],
  );
  await client.run(
    `
      UPDATE workout_sets
      SET status = 'halted', locked = 1, updated_at = CURRENT_TIMESTAMP
      WHERE lift_id IN (
        SELECT lifts.id
        FROM lifts
        INNER JOIN workouts ON workouts.id = lifts.workout_id
        WHERE workouts.program_id = ?
      )
    `,
    [programId],
  );
}

function validateTemplateForProgramStart(template: TemplateAggregate): void {
  if (template.days.length === 0) {
    throw new Error("Template has no workout days.");
  }

  const emptyDay = template.days.find((day) => day.exerciseIds.length === 0);

  if (emptyDay) {
    throw new Error(`Template day ${emptyDay.order} has no exercises.`);
  }
}

async function loadLastInsertId(client: DatabaseClient): Promise<number> {
  const rows = await client.query<LastInsertIdRow>("SELECT last_insert_rowid() AS id");
  const id = rows[0]?.id;

  if (!id) {
    throw new Error("Failed to load inserted row id.");
  }

  return id;
}
