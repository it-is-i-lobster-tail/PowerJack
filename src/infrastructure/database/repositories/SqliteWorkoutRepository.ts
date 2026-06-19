import type { EntityId } from "../../../domain/ids";
import type { Program } from "../../../domain/programs/Program";
import { isPowerJackStatus, type PowerJackStatus } from "../../../domain/status";
import type {
  ActiveWorkoutLiftView,
  ActiveWorkoutSetView,
  ActiveWorkoutView,
  ActiveWorkoutWeekItem,
  Workout,
} from "../../../domain/workouts/Workout";
import type { WorkoutRepository } from "../../../domain/workouts/WorkoutRepository";
import type { DatabaseClient } from "../DatabaseClient";

interface AppStateActiveWorkoutRow extends Record<string, unknown> {
  active_workout_id: number | null;
}

interface WorkoutHeaderRow extends Record<string, unknown> {
  program_id: number;
  program_name: string;
  program_length_weeks: number;
  program_status: string;
  program_locked: number;
  template_id: number;
  program_created_at: string;
  program_updated_at: string;
  workout_id: number;
  workout_order: number;
  workout_day: number;
  program_week: number;
  hidden: number;
  workout_locked: number;
  workout_status: string;
  workout_created_at: string;
  workout_updated_at: string;
}

interface WeekWorkoutRow extends Record<string, unknown> {
  id: number;
  workout_day: number;
  status: string;
  locked: number;
}

interface LiftSetRow extends Record<string, unknown> {
  lift_id: number;
  exercise_id: number;
  exercise_name: string;
  lift_order: number;
  lift_status: string;
  lift_locked: number;
  feedback_submitted: number;
  set_id: number;
  set_order: number;
  planned_reps: number | null;
  actual_reps: number | null;
  planned_weight: number | null;
  actual_weight: number | null;
  set_status: string;
  set_locked: number;
}

interface SetMutationRow extends Record<string, unknown> {
  lift_id: number;
  workout_id: number;
  set_locked: number;
  workout_locked: number;
  workout_status: string;
}

interface LiftFeedbackMutationRow extends Record<string, unknown> {
  workout_id: number;
  lift_locked: number;
  lift_status: string;
  workout_locked: number;
  workout_status: string;
}

interface CountRow extends Record<string, unknown> {
  count: number;
}

interface FinishWorkoutRow extends Record<string, unknown> {
  workout_id: number;
  program_id: number;
  template_id: number;
  program_week: number;
  workout_day: number;
  program_length_weeks: number;
  workout_locked: number;
}

interface WorkoutIdRow extends Record<string, unknown> {
  id: number;
}

interface ProgramIdRow extends Record<string, unknown> {
  program_id: number;
}

interface LiftIdRow extends Record<string, unknown> {
  id: number;
}

interface TemplateLiftRow extends Record<string, unknown> {
  workout_order: number;
  exercise_id: number;
  lift_order: number;
}

interface PreviousSetRow extends Record<string, unknown> {
  order: number;
  actual_reps: number | null;
  actual_weight: number | null;
}

interface LastInsertIdRow extends Record<string, unknown> {
  id: number;
}

export class SqliteWorkoutRepository implements WorkoutRepository {
  constructor(private readonly db: DatabaseClient) {}

  async loadActive(): Promise<ActiveWorkoutView | null> {
    const rows = await this.db.query<AppStateActiveWorkoutRow>(
      "SELECT active_workout_id FROM app_state WHERE id = 1",
    );
    const activeWorkoutId = rows[0]?.active_workout_id;

    if (!activeWorkoutId) {
      return null;
    }

    return this.loadWorkoutView(activeWorkoutId);
  }

  async loadWorkoutView(workoutId: EntityId): Promise<ActiveWorkoutView | null> {
    const headerRows = await this.db.query<WorkoutHeaderRow>(
      `
        SELECT
          programs.id AS program_id,
          programs.name AS program_name,
          programs.program_length_weeks,
          programs.status AS program_status,
          programs.locked AS program_locked,
          programs.template_id,
          programs.created_at AS program_created_at,
          programs.updated_at AS program_updated_at,
          workouts.id AS workout_id,
          workouts."order" AS workout_order,
          workouts.workout_day,
          workouts.program_week,
          workouts.hidden,
          workouts.locked AS workout_locked,
          workouts.status AS workout_status,
          workouts.created_at AS workout_created_at,
          workouts.updated_at AS workout_updated_at
        FROM workouts
        INNER JOIN programs ON programs.id = workouts.program_id
        WHERE workouts.id = ?
      `,
      [workoutId],
    );
    const header = headerRows[0];

    if (!header) {
      return null;
    }

    const program = mapProgram(header);
    const workout = mapWorkout(header);
    const [weekRows, liftSetRows] = await Promise.all([
      this.db.query<WeekWorkoutRow>(
        `
          SELECT id, workout_day, status, locked
          FROM workouts
          WHERE program_id = ? AND program_week = ?
          ORDER BY workout_day ASC
        `,
        [program.id, workout.programWeek],
      ),
      this.db.query<LiftSetRow>(
        `
          SELECT
            lifts.id AS lift_id,
            lifts.exercise_id,
            exercises.name AS exercise_name,
            lifts."order" AS lift_order,
            lifts.status AS lift_status,
            lifts.locked AS lift_locked,
            CASE WHEN feedback.id IS NULL THEN 0 ELSE 1 END AS feedback_submitted,
            workout_sets.id AS set_id,
            workout_sets."order" AS set_order,
            workout_sets.planned_reps,
            workout_sets.actual_reps,
            workout_sets.planned_weight,
            workout_sets.actual_weight,
            workout_sets.status AS set_status,
            workout_sets.locked AS set_locked
          FROM lifts
          INNER JOIN exercises ON exercises.id = lifts.exercise_id
          INNER JOIN workout_sets ON workout_sets.lift_id = lifts.id
          LEFT JOIN feedback ON feedback.lift_id = lifts.id
          WHERE lifts.workout_id = ?
          ORDER BY lifts."order" ASC, workout_sets."order" ASC
        `,
        [workout.id],
      ),
    ]);

    const weekWorkouts = weekRows.map(mapWeekWorkout);
    const lifts = mapLiftSetRows(liftSetRows);
    const totalSets = lifts.reduce((total, lift) => total + lift.sets.length, 0);
    const completedSets = lifts.reduce(
      (total, lift) => total + lift.sets.filter((set) => set.status === "complete").length,
      0,
    );
    const currentWeekIndex = weekWorkouts.findIndex((item) => item.id === workout.id);

    return {
      program,
      workout,
      weekWorkouts,
      previousWorkoutId:
        currentWeekIndex > 0 ? weekWorkouts[currentWeekIndex - 1]?.id ?? null : null,
      nextWorkoutId:
        currentWeekIndex >= 0 && currentWeekIndex < weekWorkouts.length - 1
          ? weekWorkouts[currentWeekIndex + 1]?.id ?? null
          : null,
      completedSets,
      totalSets,
      canFinish:
        workout.status === "active" &&
        !workout.locked &&
        totalSets > 0 &&
        completedSets === totalSets &&
        lifts.every((lift) => lift.status === "complete" && lift.feedbackSubmitted),
      isReadOnly: workout.locked || workout.status !== "active",
      lifts,
    };
  }

  async updateSetActuals(input: {
    setId: EntityId;
    actualReps: number | null;
    actualWeight: number | null;
  }): Promise<ActiveWorkoutView> {
    const workoutId = await this.db.transaction(async (client) => {
      const rows = await client.query<SetMutationRow>(
        `
          SELECT
            workout_sets.lift_id,
            lifts.workout_id,
            workout_sets.locked AS set_locked,
            workouts.locked AS workout_locked,
            workouts.status AS workout_status
          FROM workout_sets
          INNER JOIN lifts ON lifts.id = workout_sets.lift_id
          INNER JOIN workouts ON workouts.id = lifts.workout_id
          WHERE workout_sets.id = ?
        `,
        [input.setId],
      );
      const row = rows[0];

      if (!row) {
        throw new Error("Workout set was not found.");
      }

      if (row.set_locked || row.workout_locked || row.workout_status !== "active") {
        throw new Error("This set is locked.");
      }

      const nextStatus: PowerJackStatus =
        input.actualReps !== null && input.actualWeight !== null ? "complete" : "active";

      await client.run(
        `
          UPDATE workout_sets
          SET
            actual_reps = ?,
            actual_weight = ?,
            status = ?,
            updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [input.actualReps, input.actualWeight, nextStatus, input.setId],
      );

      const incompleteRows = await client.query<CountRow>(
        `
          SELECT COUNT(*) AS count
          FROM workout_sets
          WHERE lift_id = ? AND status != 'complete'
        `,
        [row.lift_id],
      );
      const liftStatus: PowerJackStatus = (incompleteRows[0]?.count ?? 0) === 0 ? "complete" : "active";

      await client.run(
        `
          UPDATE lifts
          SET status = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [liftStatus, row.lift_id],
      );

      await client.run(
        `
          UPDATE app_state
          SET active_lift_id = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = 1
        `,
        [row.lift_id],
      );

      return row.workout_id;
    });

    const view = await this.loadWorkoutView(workoutId);

    if (!view) {
      throw new Error("Workout could not be loaded after set update.");
    }

    return view;
  }

  async submitLiftFeedback(input: {
    liftId: EntityId;
    levelOfPain: number;
    levelOfEffort: number;
  }): Promise<ActiveWorkoutView> {
    validateFeedbackValue(input.levelOfPain);
    validateFeedbackValue(input.levelOfEffort);

    const workoutId = await this.db.transaction(async (client) => {
      const rows = await client.query<LiftFeedbackMutationRow>(
        `
          SELECT
            lifts.workout_id,
            lifts.locked AS lift_locked,
            lifts.status AS lift_status,
            workouts.locked AS workout_locked,
            workouts.status AS workout_status
          FROM lifts
          INNER JOIN workouts ON workouts.id = lifts.workout_id
          WHERE lifts.id = ?
        `,
        [input.liftId],
      );
      const row = rows[0];

      if (!row) {
        throw new Error("Lift was not found.");
      }

      if (row.lift_locked || row.workout_locked || row.workout_status !== "active") {
        throw new Error("This lift is locked.");
      }

      if (row.lift_status !== "complete") {
        throw new Error("Complete this lift before saving feedback.");
      }

      await client.run(
        `
          INSERT OR IGNORE INTO feedback
            (level_of_pain, level_of_effort, lift_id, created_at, updated_at)
          VALUES (?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `,
        [input.levelOfPain, input.levelOfEffort, input.liftId],
      );

      return row.workout_id;
    });

    const view = await this.loadWorkoutView(workoutId);

    if (!view) {
      throw new Error("Workout could not be loaded after feedback.");
    }

    return view;
  }

  async finishWorkout(workoutId: EntityId): Promise<ActiveWorkoutView | null> {
    const nextWorkoutId = await this.db.transaction(async (client) => {
      const rows = await client.query<FinishWorkoutRow>(
        `
          SELECT
            workouts.id AS workout_id,
            workouts.program_id,
            programs.template_id,
            workouts.program_week,
            workouts.workout_day,
            programs.program_length_weeks,
            workouts.locked AS workout_locked
          FROM workouts
          INNER JOIN programs ON programs.id = workouts.program_id
          WHERE workouts.id = ?
        `,
        [workoutId],
      );
      const workout = rows[0];

      if (!workout) {
        throw new Error("Workout was not found.");
      }

      if (workout.workout_locked) {
        throw new Error("This workout is locked.");
      }

      const incompleteRows = await client.query<CountRow>(
        `
          SELECT COUNT(*) AS count
          FROM workout_sets
          INNER JOIN lifts ON lifts.id = workout_sets.lift_id
          WHERE lifts.workout_id = ? AND workout_sets.status != 'complete'
        `,
        [workoutId],
      );

      if ((incompleteRows[0]?.count ?? 0) > 0) {
        throw new Error("Complete every set before finishing the workout.");
      }

      const missingFeedbackRows = await client.query<CountRow>(
        `
          SELECT COUNT(*) AS count
          FROM lifts
          LEFT JOIN feedback ON feedback.lift_id = lifts.id
          WHERE
            lifts.workout_id = ?
            AND lifts.status = 'complete'
            AND feedback.id IS NULL
        `,
        [workoutId],
      );

      if ((missingFeedbackRows[0]?.count ?? 0) > 0) {
        throw new Error("Submit feedback for every completed lift before finishing the workout.");
      }

      await lockCompletedWorkout(client, workoutId);

      let nextId = await findNextWorkoutInWeek(client, workout);

      if (!nextId && workout.program_week < workout.program_length_weeks) {
        const nextWeek = workout.program_week + 1;
        const existingNextWeekRows = await client.query<CountRow>(
          "SELECT COUNT(*) AS count FROM workouts WHERE program_id = ? AND program_week = ?",
          [workout.program_id, nextWeek],
        );

        if ((existingNextWeekRows[0]?.count ?? 0) === 0) {
          await createProgramWeek(client, {
            programId: workout.program_id,
            templateId: workout.template_id,
            programWeek: nextWeek,
          });
        }

        const firstNextWeekRows = await client.query<WorkoutIdRow>(
          `
            SELECT id
            FROM workouts
            WHERE program_id = ? AND program_week = ?
            ORDER BY workout_day ASC
            LIMIT 1
          `,
          [workout.program_id, nextWeek],
        );
        nextId = firstNextWeekRows[0]?.id ?? null;
      }

      if (!nextId) {
        await client.run(
          `
            UPDATE programs
            SET status = 'complete', locked = 1, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `,
          [workout.program_id],
        );
        await client.run(
          `
            UPDATE app_state
            SET
              active_program_id = NULL,
              active_workout_id = NULL,
              active_lift_id = NULL,
              updated_at = CURRENT_TIMESTAMP
            WHERE id = 1
          `,
        );

        return null;
      }

      await activateWorkout(client, nextId);
      return nextId;
    });

    return nextWorkoutId ? this.loadWorkoutView(nextWorkoutId) : null;
  }
}

function mapProgram(row: WorkoutHeaderRow): Program {
  return {
    id: row.program_id,
    name: row.program_name,
    programLengthWeeks: row.program_length_weeks,
    status: mapStatus(row.program_status),
    locked: Boolean(row.program_locked),
    templateId: row.template_id,
    createdAt: row.program_created_at,
    updatedAt: row.program_updated_at,
  };
}

function mapWorkout(row: WorkoutHeaderRow): Workout {
  return {
    id: row.workout_id,
    order: row.workout_order,
    workoutDay: row.workout_day,
    programWeek: row.program_week,
    hidden: Boolean(row.hidden),
    locked: Boolean(row.workout_locked),
    status: mapStatus(row.workout_status),
    programId: row.program_id,
    createdAt: row.workout_created_at,
    updatedAt: row.workout_updated_at,
  };
}

function mapWeekWorkout(row: WeekWorkoutRow): ActiveWorkoutWeekItem {
  return {
    id: row.id,
    workoutDay: row.workout_day,
    status: mapStatus(row.status),
    locked: Boolean(row.locked),
  };
}

function mapLiftSetRows(rows: LiftSetRow[]): ActiveWorkoutLiftView[] {
  const liftMap = new Map<number, ActiveWorkoutLiftView>();

  for (const row of rows) {
    const existingLift = liftMap.get(row.lift_id);
    const lift =
      existingLift ??
      {
        id: row.lift_id,
        exerciseId: row.exercise_id,
        exerciseName: row.exercise_name,
        order: row.lift_order,
        status: mapStatus(row.lift_status),
        locked: Boolean(row.lift_locked),
        feedbackSubmitted: Boolean(row.feedback_submitted),
        sets: [],
      };

    const setView: ActiveWorkoutSetView = {
      id: row.set_id,
      order: row.set_order,
      plannedReps: row.planned_reps,
      actualReps: row.actual_reps,
      plannedWeight: row.planned_weight,
      actualWeight: row.actual_weight,
      status: mapStatus(row.set_status),
      locked: Boolean(row.set_locked),
    };

    lift.sets.push(setView);
    liftMap.set(row.lift_id, lift);
  }

  return Array.from(liftMap.values());
}

function mapStatus(value: string): PowerJackStatus {
  if (!isPowerJackStatus(value)) {
    throw new Error(`Unknown PowerJack status: ${value}`);
  }

  return value;
}

function validateFeedbackValue(value: number): void {
  if (!Number.isInteger(value) || value < 1 || value > 5) {
    throw new Error("Choose a feedback value from 1 to 5.");
  }
}

async function lockCompletedWorkout(client: DatabaseClient, workoutId: EntityId): Promise<void> {
  await client.run(
    `
      UPDATE workout_sets
      SET status = 'complete', locked = 1, updated_at = CURRENT_TIMESTAMP
      WHERE lift_id IN (SELECT id FROM lifts WHERE workout_id = ?)
    `,
    [workoutId],
  );
  await client.run(
    `
      UPDATE lifts
      SET status = 'complete', locked = 1, updated_at = CURRENT_TIMESTAMP
      WHERE workout_id = ?
    `,
    [workoutId],
  );
  await client.run(
    `
      UPDATE workouts
      SET status = 'complete', locked = 1, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `,
    [workoutId],
  );
}

async function findNextWorkoutInWeek(
  client: DatabaseClient,
  workout: FinishWorkoutRow,
): Promise<EntityId | null> {
  const rows = await client.query<WorkoutIdRow>(
    `
      SELECT id
      FROM workouts
      WHERE program_id = ? AND program_week = ? AND workout_day > ?
      ORDER BY workout_day ASC
      LIMIT 1
    `,
    [workout.program_id, workout.program_week, workout.workout_day],
  );

  return rows[0]?.id ?? null;
}

async function activateWorkout(client: DatabaseClient, workoutId: EntityId): Promise<void> {
  const programRows = await client.query<ProgramIdRow>("SELECT program_id FROM workouts WHERE id = ?", [
    workoutId,
  ]);
  const programId = programRows[0]?.program_id;

  if (!programId) {
    throw new Error("Workout program could not be loaded.");
  }

  await client.run(
    `
      UPDATE workouts
      SET status = 'active', locked = 0, hidden = 0, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `,
    [workoutId],
  );
  await client.run(
    `
      UPDATE lifts
      SET status = 'active', locked = 0, hidden = 0, updated_at = CURRENT_TIMESTAMP
      WHERE workout_id = ?
    `,
    [workoutId],
  );
  await client.run(
    `
      UPDATE workout_sets
      SET status = 'active', locked = 0, hidden = 0, updated_at = CURRENT_TIMESTAMP
      WHERE lift_id IN (SELECT id FROM lifts WHERE workout_id = ?)
    `,
    [workoutId],
  );

  const firstLiftRows = await client.query<LiftIdRow>(
    `
      SELECT id
      FROM lifts
      WHERE workout_id = ?
      ORDER BY "order" ASC
      LIMIT 1
    `,
    [workoutId],
  );

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
    [programId, workoutId, firstLiftRows[0]?.id ?? null],
  );
}

async function createProgramWeek(
  client: DatabaseClient,
  input: { programId: EntityId; templateId: EntityId; programWeek: number },
): Promise<void> {
  const templateRows = await client.query<TemplateLiftRow>(
    `
      SELECT
        workout_templates."order" AS workout_order,
        lift_templates.exercise_id,
        lift_templates."order" AS lift_order
      FROM workout_templates
      INNER JOIN lift_templates ON lift_templates.workout_template_id = workout_templates.id
      WHERE workout_templates.template_id = ?
      ORDER BY workout_templates."order" ASC, lift_templates."order" ASC
    `,
    [input.templateId],
  );
  const liftsByDay = new Map<number, TemplateLiftRow[]>();

  for (const row of templateRows) {
    liftsByDay.set(row.workout_order, [...(liftsByDay.get(row.workout_order) ?? []), row]);
  }

  for (const [dayOrder, liftRows] of liftsByDay.entries()) {
    await client.run(
      `
        INSERT INTO workouts
          ("order", workout_day, program_week, hidden, locked, status, program_id, created_at, updated_at)
        VALUES (?, ?, ?, 0, 1, 'planned', ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      `,
      [dayOrder, dayOrder, input.programWeek, input.programId],
    );

    const workoutId = await loadLastInsertId(client);

    for (const liftRow of liftRows) {
      await client.run(
        `
          INSERT INTO lifts
            (exercise_id, workout_id, locked, hidden, "order", status, planned, created_at, updated_at)
          VALUES (?, ?, 1, 0, ?, 'planned', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `,
        [liftRow.exercise_id, workoutId, liftRow.lift_order],
      );

      const liftId = await loadLastInsertId(client);
      const previousSets = await loadPreviousWeekSets(client, {
        programId: input.programId,
        programWeek: input.programWeek - 1,
        workoutDay: dayOrder,
        liftOrder: liftRow.lift_order,
      });
      const setPlans =
        previousSets.length > 0
          ? previousSets
          : [
              { order: 1, actual_reps: null, actual_weight: null },
              { order: 2, actual_reps: null, actual_weight: null },
            ];

      for (const setPlan of setPlans) {
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
            VALUES (?, NULL, ?, NULL, ?, ?, 1, 0, 'planned', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          `,
          [
            setPlan.actual_reps === null ? null : setPlan.actual_reps + 1,
            setPlan.actual_weight,
            setPlan.order,
            liftId,
          ],
        );
      }
    }
  }
}

async function loadPreviousWeekSets(
  client: DatabaseClient,
  input: { programId: EntityId; programWeek: number; workoutDay: number; liftOrder: number },
): Promise<PreviousSetRow[]> {
  return client.query<PreviousSetRow>(
    `
      SELECT
        workout_sets."order",
        workout_sets.actual_reps,
        workout_sets.actual_weight
      FROM workouts
      INNER JOIN lifts ON lifts.workout_id = workouts.id
      INNER JOIN workout_sets ON workout_sets.lift_id = lifts.id
      WHERE
        workouts.program_id = ?
        AND workouts.program_week = ?
        AND workouts.workout_day = ?
        AND lifts."order" = ?
      ORDER BY workout_sets."order" ASC
    `,
    [input.programId, input.programWeek, input.workoutDay, input.liftOrder],
  );
}

async function loadLastInsertId(client: DatabaseClient): Promise<number> {
  const rows = await client.query<LastInsertIdRow>("SELECT last_insert_rowid() AS id");
  const id = rows[0]?.id;

  if (!id) {
    throw new Error("Failed to load inserted row id.");
  }

  return id;
}
