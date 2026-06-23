import type { AppState } from "../../../domain/app-state/AppState";
import type { ProgramListSummary } from "../../../domain/programs/ProgramList";
import type {
  PersistedProgramScheduleCell,
  ProgramOverviewFocusMuscle,
  ProgramOverviewSnapshot,
  ProgramOverviewStatusCounts,
} from "../../../domain/programs/ProgramOverview";
import {
  buildProgramSchedule,
  calculateProgramProgress,
  createProgramOverviewStatusCounts,
} from "../../../domain/programs/ProgramOverview";
import type { ProgramRepository } from "../../../domain/programs/ProgramRepository";
import { isPowerJackStatus, type PowerJackStatus } from "../../../domain/status";
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

interface ProgramListHeaderRow extends Record<string, unknown> {
  id: number;
  created_at: string;
  updated_at: string;
}

interface ProgramOverviewHeaderRow extends Record<string, unknown> {
  id: number;
  name: string;
  program_length_weeks: number;
  status: string;
  locked: number;
  template_id: number;
  template_name: string;
  workouts_per_week: number;
  focus_muscles: string | null;
}

interface ProgramOverviewWorkoutRow extends Record<string, unknown> {
  workout_id: number;
  program_week: number;
  workout_day: number;
  total_sets: number;
  planned_sets: number;
  active_sets: number;
  complete_sets: number;
  halted_sets: number;
  skipped_sets: number;
}

interface TemplateDaySetCountRow extends Record<string, unknown> {
  workout_day: number;
  set_count: number;
}

export class SqliteProgramRepository implements ProgramRepository {
  constructor(private readonly db: DatabaseClient) {}

  async listSummaries(): Promise<ProgramListSummary[]> {
    const rows = await this.db.query<ProgramListHeaderRow>(
      `
        SELECT id, created_at, updated_at
        FROM programs
        ORDER BY created_at DESC, id DESC
      `,
    );
    const overviews = await Promise.all(rows.map((row) => this.loadOverview(row.id)));

    return rows.flatMap((row, index) => {
      const overview = overviews[index];

      if (!overview) {
        return [];
      }

      return [
        {
          id: overview.program.id,
          name: overview.program.name,
          status: overview.program.status,
          templateName: overview.program.templateName,
          focusMuscles: overview.program.focusMuscles,
          progressPercent: overview.program.progressPercent,
          createdAt: row.created_at,
          updatedAt: row.updated_at,
        },
      ];
    });
  }

  async loadOverview(programId: number): Promise<ProgramOverviewSnapshot | null> {
    const headerRows = await this.db.query<ProgramOverviewHeaderRow>(
      `
        SELECT
          programs.id,
          programs.name,
          programs.program_length_weeks,
          programs.status,
          programs.locked,
          programs.template_id,
          templates.name AS template_name,
          templates.workouts_per_week,
          (
            SELECT GROUP_CONCAT(focus_muscles.id || ':' || focus_muscles.name, '|')
            FROM (
              SELECT muscles.id, muscles.name
              FROM template_focus_muscles
              INNER JOIN muscles ON muscles.id = template_focus_muscles.muscle_id
              WHERE template_focus_muscles.template_id = templates.id
              ORDER BY muscles.name ASC
            ) AS focus_muscles
          ) AS focus_muscles
        FROM programs
        INNER JOIN templates ON templates.id = programs.template_id
        WHERE programs.id = ?
      `,
      [programId],
    );
    const header = headerRows[0];

    if (!header) {
      return null;
    }

    const [workoutRows, templateDayRows] = await Promise.all([
      this.db.query<ProgramOverviewWorkoutRow>(
        `
          SELECT
            workouts.id AS workout_id,
            workouts.program_week,
            workouts.workout_day,
            COUNT(workout_sets.id) AS total_sets,
            SUM(CASE WHEN workout_sets.status = 'planned' THEN 1 ELSE 0 END) AS planned_sets,
            SUM(CASE WHEN workout_sets.status = 'active' THEN 1 ELSE 0 END) AS active_sets,
            SUM(CASE WHEN workout_sets.status = 'complete' THEN 1 ELSE 0 END) AS complete_sets,
            SUM(CASE WHEN workout_sets.status = 'halted' THEN 1 ELSE 0 END) AS halted_sets,
            SUM(CASE WHEN workout_sets.status = 'skipped' THEN 1 ELSE 0 END) AS skipped_sets
          FROM workouts
          LEFT JOIN lifts ON lifts.workout_id = workouts.id
          LEFT JOIN workout_sets ON workout_sets.lift_id = lifts.id
          WHERE workouts.program_id = ?
          GROUP BY workouts.id
          ORDER BY workouts.program_week ASC, workouts.workout_day ASC
        `,
        [programId],
      ),
      this.db.query<TemplateDaySetCountRow>(
        `
          SELECT
            workout_templates."order" AS workout_day,
            COUNT(lift_templates.id) * 2 AS set_count
          FROM workout_templates
          LEFT JOIN lift_templates ON lift_templates.workout_template_id = workout_templates.id
          WHERE workout_templates.template_id = ?
          GROUP BY workout_templates.id
          ORDER BY workout_templates."order" ASC
        `,
        [header.template_id],
      ),
    ]);

    const schedule = buildProgramSchedule({
      programLengthWeeks: header.program_length_weeks,
      workoutsPerWeek: header.workouts_per_week,
      persistedCells: workoutRows.map(mapProgramOverviewWorkoutRow),
      plannedSetCountsByDay: new Map(
        templateDayRows.map((row) => [row.workout_day, row.set_count] as const),
      ),
    });
    const progress = calculateProgramProgress(schedule);

    return {
      program: {
        id: header.id,
        name: header.name,
        status: mapStatus(header.status),
        locked: Boolean(header.locked),
        templateId: header.template_id,
        templateName: header.template_name,
        programLengthWeeks: header.program_length_weeks,
        workoutsPerWeek: header.workouts_per_week,
        focusMuscles: parseFocusMuscles(header.focus_muscles),
        completedSets: progress.completedSets,
        totalSets: progress.totalSets,
        progressPercent: progress.progressPercent,
      },
      schedule,
    };
  }

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
            rest_timer_state = 'idle',
            rest_timer_workout_id = NULL,
            rest_timer_lift_id = NULL,
            rest_timer_next_set_id = NULL,
            rest_timer_started_at = NULL,
            rest_timer_duration_seconds = 120,
            rest_timer_remaining_seconds = 0,
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

function mapProgramOverviewWorkoutRow(row: ProgramOverviewWorkoutRow): PersistedProgramScheduleCell {
  const statusCounts: ProgramOverviewStatusCounts = createProgramOverviewStatusCounts({
    planned: row.planned_sets ?? 0,
    active: row.active_sets ?? 0,
    complete: row.complete_sets ?? 0,
    halted: row.halted_sets ?? 0,
    skipped: row.skipped_sets ?? 0,
  });

  return {
    workoutId: row.workout_id,
    week: row.program_week,
    day: row.workout_day,
    totalSets: row.total_sets,
    statusCounts,
  };
}

function parseFocusMuscles(value: string | null): ProgramOverviewFocusMuscle[] {
  if (!value) {
    return [];
  }

  return value.split("|").map((item) => {
    const [id, name] = item.split(":");

    return {
      id: Number(id),
      name,
    };
  });
}

function mapStatus(value: string): PowerJackStatus {
  if (!isPowerJackStatus(value)) {
    throw new Error(`Unknown PowerJack status: ${value}`);
  }

  return value;
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
      SET
        status = CASE WHEN status = 'complete' THEN status ELSE 'halted' END,
        locked = 1,
        updated_at = CURRENT_TIMESTAMP
      WHERE program_id = ?
    `,
    [programId],
  );
  await client.run(
    `
      UPDATE lifts
      SET
        status = CASE WHEN status = 'complete' THEN status ELSE 'halted' END,
        locked = 1,
        updated_at = CURRENT_TIMESTAMP
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
      SET
        status = CASE WHEN status = 'complete' THEN status ELSE 'halted' END,
        locked = 1,
        updated_at = CURRENT_TIMESTAMP
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
