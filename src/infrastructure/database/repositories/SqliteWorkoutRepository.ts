import type { EntityId } from "../../../domain/ids";
import type { Program } from "../../../domain/programs/Program";
import { isPowerJackStatus, type PowerJackStatus } from "../../../domain/status";
import {
  manualCheckinStatuses,
  type ActiveWorkoutLiftView,
  type ActiveWorkoutSetView,
  type ActiveWorkoutView,
  type ActiveWorkoutWeekItem,
  type ManualCheckinStatus,
  type Workout,
} from "../../../domain/workouts/Workout";
import {
  generateNextLiftPrescription,
  maxWorkingSets,
  type NextLiftPrescription,
  type ProgressionLiftHistory,
  type ProgressionLiftSet,
} from "../../../domain/workouts/progression/generateNextLiftPrescription";
import type {
  ManualCheckinDecision,
  WorkoutRepository,
} from "../../../domain/workouts/WorkoutRepository";
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
  reps_only: number;
  time_based: number;
  lift_order: number;
  lift_status: string;
  lift_locked: number;
  feedback_submitted: number;
  manual_checkin_status: string;
  manual_checkin_source_lift_id: number | null;
  manual_checkin_source_pain: number | null;
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
  reps_only: number;
}

interface LiftMutationRow extends Record<string, unknown> {
  lift_id: number;
  exercise_id: number;
  workout_id: number;
  workout_day: number;
  lift_order: number;
  lift_locked: number;
  lift_status: string;
  manual_checkin_status: string;
  workout_locked: number;
  workout_status: string;
  program_id: number;
  template_id: number;
}

interface SetCountRow extends Record<string, unknown> {
  count: number;
  max_order: number | null;
}

interface LastSetRow extends Record<string, unknown> {
  id: number;
  actual_reps: number | null;
  actual_weight: number | null;
  status: string;
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
  reps_only: number;
  lift_order: number;
  primary_muscle_id: number;
  min_reps_hypertrophy: number;
  max_reps_hypertrophy: number;
}

interface LiftHistoryRow extends Record<string, unknown> {
  lift_id: number;
  program_week: number;
  lift_status: string;
  level_of_pain: number | null;
  level_of_effort: number | null;
  manual_checkin_source_lift_id: number | null;
}

interface LiftHistorySetRow extends Record<string, unknown> {
  order: number;
  planned_reps: number | null;
  planned_weight: number | null;
  actual_reps: number | null;
  actual_weight: number | null;
  status: string;
}

interface FocusMuscleRow extends Record<string, unknown> {
  muscle_id: number;
}

interface ResolveManualCheckinRow extends Record<string, unknown> {
  lift_id: number;
  workout_id: number;
  manual_checkin_status: string;
  workout_locked: number;
  workout_status: string;
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
            exercises.reps_only,
            exercises.time_based,
            lifts."order" AS lift_order,
            lifts.status AS lift_status,
            lifts.locked AS lift_locked,
            CASE WHEN feedback.id IS NULL THEN 0 ELSE 1 END AS feedback_submitted,
            lifts.manual_checkin_status,
            lifts.manual_checkin_source_lift_id,
            source_feedback.level_of_pain AS manual_checkin_source_pain,
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
          LEFT JOIN feedback AS source_feedback ON source_feedback.lift_id = lifts.manual_checkin_source_lift_id
          WHERE lifts.workout_id = ?
          ORDER BY lifts."order" ASC, workout_sets."order" ASC
        `,
        [workout.id],
      ),
    ]);

    const weekWorkouts = weekRows.map(mapWeekWorkout);
    const lifts = mapLiftSetRows(liftSetRows);
    const countableSets = lifts.flatMap((lift) => lift.sets).filter((set) => set.status !== "skipped");
    const completedCountableSets = countableSets.filter((set) => set.status === "completed");
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
      completedSets: completedCountableSets.length,
      totalSets: countableSets.length,
      canFinish:
        workout.status === "active" &&
        !workout.locked &&
        lifts.length > 0 &&
        completedCountableSets.length === countableSets.length &&
        lifts.every((lift) => lift.status === "skipped" || (lift.status === "completed" && lift.feedbackSubmitted)),
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
            workouts.status AS workout_status,
            exercises.reps_only
          FROM workout_sets
          INNER JOIN lifts ON lifts.id = workout_sets.lift_id
          INNER JOIN exercises ON exercises.id = lifts.exercise_id
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

      const repsOnly = Boolean(row.reps_only);
      const nextActualWeight = repsOnly ? null : input.actualWeight;
      const nextStatus: PowerJackStatus =
        input.actualReps !== null && (repsOnly || nextActualWeight !== null) ? "completed" : "active";

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
        [input.actualReps, nextActualWeight, nextStatus, input.setId],
      );

      const incompleteRows = await client.query<CountRow>(
        `
          SELECT COUNT(*) AS count
          FROM workout_sets
          WHERE lift_id = ? AND status NOT IN ('completed', 'skipped')
        `,
        [row.lift_id],
      );
      const liftStatus: PowerJackStatus = (incompleteRows[0]?.count ?? 0) === 0 ? "completed" : "active";

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

  async addSetToLift(input: { liftId: EntityId }): Promise<ActiveWorkoutView> {
    const workoutId = await this.db.transaction(async (client) => {
      const lift = await loadEditableLiftForMutation(client, input.liftId);
      const setRows = await client.query<SetCountRow>(
        'SELECT COUNT(*) AS count, MAX("order") AS max_order FROM workout_sets WHERE lift_id = ?',
        [input.liftId],
      );
      const setCount = setRows[0]?.count ?? 0;

      if (setCount >= maxWorkingSets) {
        throw new Error(`A lift can have at most ${maxWorkingSets} sets.`);
      }

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
          VALUES (NULL, NULL, NULL, NULL, ?, ?, 0, 0, 'active', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `,
        [(setRows[0]?.max_order ?? 0) + 1, input.liftId],
      );
      await client.run(
        `
          UPDATE lifts
          SET status = 'active', updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [input.liftId],
      );
      await client.run(
        `
          UPDATE app_state
          SET active_lift_id = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = 1
        `,
        [input.liftId],
      );

      return lift.workout_id;
    });

    const view = await this.loadWorkoutView(workoutId);

    if (!view) {
      throw new Error("Workout could not be loaded after set add.");
    }

    return view;
  }

  async removeLastSetFromLift(input: { liftId: EntityId }): Promise<ActiveWorkoutView> {
    const workoutId = await this.db.transaction(async (client) => {
      const lift = await loadEditableLiftForMutation(client, input.liftId);
      const setRows = await client.query<SetCountRow>(
        'SELECT COUNT(*) AS count, MAX("order") AS max_order FROM workout_sets WHERE lift_id = ?',
        [input.liftId],
      );
      const setCount = setRows[0]?.count ?? 0;

      if (setCount <= 1) {
        throw new Error("A lift must have at least one set.");
      }

      const lastSetRows = await client.query<LastSetRow>(
        `
          SELECT id, actual_reps, actual_weight, status
          FROM workout_sets
          WHERE lift_id = ?
          ORDER BY "order" DESC
          LIMIT 1
        `,
        [input.liftId],
      );
      const lastSet = lastSetRows[0];

      if (!lastSet) {
        throw new Error("Workout set was not found.");
      }

      await client.run("DELETE FROM workout_sets WHERE id = ?", [lastSet.id]);
      await refreshLiftStatusFromSets(client, input.liftId);
      await client.run(
        `
          UPDATE app_state
          SET active_lift_id = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = 1
        `,
        [input.liftId],
      );

      return lift.workout_id;
    });

    const view = await this.loadWorkoutView(workoutId);

    if (!view) {
      throw new Error("Workout could not be loaded after set removal.");
    }

    return view;
  }

  async changeLiftExercise(input: {
    liftId: EntityId;
    exerciseId: EntityId;
  }): Promise<ActiveWorkoutView> {
    const workoutId = await this.db.transaction(async (client) => {
      const lift = await loadEditableLiftForMutation(client, input.liftId);
      const exerciseRows = await client.query<CountRow>(
        "SELECT COUNT(*) AS count FROM exercises WHERE id = ?",
        [input.exerciseId],
      );

      if ((exerciseRows[0]?.count ?? 0) === 0) {
        throw new Error("Exercise was not found.");
      }

      if (lift.exercise_id === input.exerciseId) {
        return lift.workout_id;
      }

      const liftTemplateRows = await client.query<CountRow>(
        `
          SELECT COUNT(*) AS count
          FROM workout_templates
          INNER JOIN lift_templates ON lift_templates.workout_template_id = workout_templates.id
          WHERE
            workout_templates.template_id = ?
            AND workout_templates."order" = ?
            AND lift_templates."order" = ?
        `,
        [lift.template_id, lift.workout_day, lift.lift_order],
      );

      if ((liftTemplateRows[0]?.count ?? 0) === 0) {
        throw new Error("Lift template was not found.");
      }

      await client.run(
        `
          UPDATE lift_templates
          SET exercise_id = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id IN (
            SELECT lift_templates.id
            FROM workout_templates
            INNER JOIN lift_templates ON lift_templates.workout_template_id = workout_templates.id
            WHERE
              workout_templates.template_id = ?
              AND workout_templates."order" = ?
              AND lift_templates."order" = ?
          )
        `,
        [input.exerciseId, lift.template_id, lift.workout_day, lift.lift_order],
      );
      await client.run(
        `
          UPDATE templates
          SET updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [lift.template_id],
      );
      await client.run("DELETE FROM feedback WHERE lift_id = ?", [input.liftId]);
      await client.run("DELETE FROM workout_sets WHERE lift_id = ?", [input.liftId]);
      await client.run(
        `
          UPDATE lifts
          SET
            exercise_id = ?,
            status = 'active',
            locked = 0,
            manual_checkin_status = 'none',
            manual_checkin_source_lift_id = NULL,
            updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [input.exerciseId, input.liftId],
      );

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
            VALUES (NULL, NULL, NULL, NULL, ?, ?, 0, 0, 'active', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          `,
          [setOrder, input.liftId],
        );
      }

      await client.run(
        `
          UPDATE app_state
          SET active_lift_id = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = 1
        `,
        [input.liftId],
      );

      return lift.workout_id;
    });

    const view = await this.loadWorkoutView(workoutId);

    if (!view) {
      throw new Error("Workout could not be loaded after exercise change.");
    }

    return view;
  }

  async submitLiftFeedback(input: {
    liftId: EntityId;
    levelOfPain: number;
    levelOfEffort: number;
  }): Promise<ActiveWorkoutView> {
    validatePainValue(input.levelOfPain);
    validateEffortValue(input.levelOfEffort);

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

      if (row.lift_status !== "completed") {
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

  async resolveManualCheckIn(input: {
    liftId: EntityId;
    decision: ManualCheckinDecision;
  }): Promise<ActiveWorkoutView> {
    const workoutId = await this.db.transaction(async (client) => {
      const rows = await client.query<ResolveManualCheckinRow>(
        `
          SELECT
            lifts.id AS lift_id,
            lifts.workout_id,
            lifts.manual_checkin_status,
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

      if (row.workout_locked || row.workout_status !== "active") {
        throw new Error("This workout is locked.");
      }

      if (row.manual_checkin_status !== "pending") {
        throw new Error("This lift does not need a manual check-in.");
      }

      if (input.decision === "skip") {
        await client.run(
          `
            UPDATE workout_sets
            SET
              actual_reps = NULL,
              actual_weight = NULL,
              status = 'skipped',
              locked = 1,
              updated_at = CURRENT_TIMESTAMP
            WHERE lift_id = ?
          `,
          [input.liftId],
        );
        await client.run(
          `
            UPDATE lifts
            SET
              status = 'skipped',
              locked = 1,
              manual_checkin_status = 'resolved',
              updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
          `,
          [input.liftId],
        );
        return row.workout_id;
      }

      if (input.decision === "reset") {
        await client.run("DELETE FROM workout_sets WHERE lift_id = ?", [input.liftId]);

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
              VALUES (NULL, NULL, NULL, NULL, ?, ?, 0, 0, 'active', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            `,
            [setOrder, input.liftId],
          );
        }
      } else if (input.decision !== "continue") {
        throw new Error("Choose a manual check-in option.");
      }

      await client.run(
        `
          UPDATE workout_sets
          SET status = 'active', locked = 0, updated_at = CURRENT_TIMESTAMP
          WHERE lift_id = ?
        `,
        [input.liftId],
      );
      await client.run(
        `
          UPDATE lifts
          SET
            status = 'active',
            locked = 0,
            manual_checkin_status = 'resolved',
            updated_at = CURRENT_TIMESTAMP
          WHERE id = ?
        `,
        [input.liftId],
      );
      await client.run(
        `
          UPDATE app_state
          SET active_lift_id = ?, updated_at = CURRENT_TIMESTAMP
          WHERE id = 1
        `,
        [input.liftId],
      );

      return row.workout_id;
    });

    const view = await this.loadWorkoutView(workoutId);

    if (!view) {
      throw new Error("Workout could not be loaded after manual check-in.");
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
          WHERE lifts.workout_id = ? AND workout_sets.status NOT IN ('completed', 'skipped')
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
            AND lifts.status = 'completed'
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
            programLengthWeeks: workout.program_length_weeks,
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
            SET status = 'completed', locked = 1, updated_at = CURRENT_TIMESTAMP
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
        repsOnly: Boolean(row.reps_only),
        timeBased: Boolean(row.time_based),
        order: row.lift_order,
        status: mapStatus(row.lift_status),
        locked: Boolean(row.lift_locked),
        feedbackSubmitted: Boolean(row.feedback_submitted),
        manualCheckinStatus: mapManualCheckinStatus(row.manual_checkin_status),
        manualCheckinSourceLiftId: row.manual_checkin_source_lift_id,
        manualCheckinSourcePain: row.manual_checkin_source_pain,
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

function mapManualCheckinStatus(value: string): ManualCheckinStatus {
  if (!manualCheckinStatuses.includes(value as ManualCheckinStatus)) {
    throw new Error(`Unknown manual check-in status: ${value}`);
  }

  return value as ManualCheckinStatus;
}

function mapProgressionSet(row: LiftHistorySetRow): ProgressionLiftSet {
  return {
    order: row.order,
    plannedReps: row.planned_reps,
    plannedWeight: row.planned_weight,
    actualReps: row.actual_reps,
    actualWeight: row.actual_weight,
    status: mapStatus(row.status),
  };
}

async function loadEditableLiftForMutation(
  client: DatabaseClient,
  liftId: EntityId,
): Promise<LiftMutationRow> {
  const rows = await client.query<LiftMutationRow>(
    `
      SELECT
        lifts.id AS lift_id,
        lifts.exercise_id,
        lifts.workout_id,
        workouts.workout_day,
        lifts."order" AS lift_order,
        lifts.locked AS lift_locked,
        lifts.status AS lift_status,
        lifts.manual_checkin_status,
        workouts.locked AS workout_locked,
        workouts.status AS workout_status,
        workouts.program_id,
        programs.template_id
      FROM lifts
      INNER JOIN workouts ON workouts.id = lifts.workout_id
      INNER JOIN programs ON programs.id = workouts.program_id
      WHERE lifts.id = ?
    `,
    [liftId],
  );
  const row = rows[0];

  if (!row) {
    throw new Error("Lift was not found.");
  }

  if (row.lift_locked || row.workout_locked || row.workout_status !== "active") {
    throw new Error("This lift is locked.");
  }

  if (row.manual_checkin_status === "pending") {
    throw new Error("Resolve manual check-in before editing this lift.");
  }

  const pendingRows = await client.query<CountRow>(
    `
      SELECT COUNT(*) AS count
      FROM lifts
      WHERE workout_id = ? AND manual_checkin_status = 'pending'
    `,
    [row.workout_id],
  );

  if ((pendingRows[0]?.count ?? 0) > 0) {
    throw new Error("Resolve manual check-in before editing this workout.");
  }

  return row;
}

async function refreshLiftStatusFromSets(client: DatabaseClient, liftId: EntityId): Promise<void> {
  const incompleteRows = await client.query<CountRow>(
    `
      SELECT COUNT(*) AS count
      FROM workout_sets
      WHERE lift_id = ? AND status NOT IN ('completed', 'skipped')
    `,
    [liftId],
  );
  const liftStatus: PowerJackStatus = (incompleteRows[0]?.count ?? 0) === 0 ? "completed" : "active";

  await client.run(
    `
      UPDATE lifts
      SET status = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `,
    [liftStatus, liftId],
  );
}

function validatePainValue(value: number): void {
  if (!Number.isInteger(value) || value < 1 || value > 5) {
    throw new Error("Choose a pain value from 1 to 5.");
  }
}

function validateEffortValue(value: number): void {
  if (!Number.isInteger(value) || value < 1 || value > 5) {
    throw new Error("Choose an effort value from 1 to 5.");
  }
}

async function lockCompletedWorkout(client: DatabaseClient, workoutId: EntityId): Promise<void> {
  await client.run(
    `
      UPDATE workout_sets
      SET
        status = CASE WHEN status = 'skipped' THEN 'skipped' ELSE 'completed' END,
        locked = 1,
        updated_at = CURRENT_TIMESTAMP
      WHERE lift_id IN (SELECT id FROM lifts WHERE workout_id = ?)
    `,
    [workoutId],
  );
  await client.run(
    `
      UPDATE lifts
      SET
        status = CASE WHEN status = 'skipped' THEN 'skipped' ELSE 'completed' END,
        locked = 1,
        updated_at = CURRENT_TIMESTAMP
      WHERE workout_id = ?
    `,
    [workoutId],
  );
  await client.run(
    `
      UPDATE workouts
      SET status = 'completed', locked = 1, updated_at = CURRENT_TIMESTAMP
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
      SET
        status = 'active',
        locked = CASE WHEN manual_checkin_status = 'pending' THEN 1 ELSE 0 END,
        hidden = 0,
        updated_at = CURRENT_TIMESTAMP
      WHERE workout_id = ?
    `,
    [workoutId],
  );
  await client.run(
    `
      UPDATE workout_sets
      SET
        status = 'active',
        locked = CASE
          WHEN lift_id IN (
            SELECT id
            FROM lifts
            WHERE workout_id = ? AND manual_checkin_status = 'pending'
          ) THEN 1
          ELSE 0
        END,
        hidden = 0,
        updated_at = CURRENT_TIMESTAMP
      WHERE lift_id IN (SELECT id FROM lifts WHERE workout_id = ?)
    `,
    [workoutId, workoutId],
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
    [programId, workoutId, firstLiftRows[0]?.id ?? null],
  );
}

async function createProgramWeek(
  client: DatabaseClient,
  input: {
    programId: EntityId;
    templateId: EntityId;
    programWeek: number;
    programLengthWeeks: number;
  },
): Promise<void> {
  const templateRows = await client.query<TemplateLiftRow>(
    `
      SELECT
        workout_templates."order" AS workout_order,
        lift_templates.exercise_id,
        exercises.reps_only,
        lift_templates."order" AS lift_order,
        exercises.primary_muscle_id,
        exercises.min_reps_hypertrophy,
        exercises.max_reps_hypertrophy
      FROM workout_templates
      INNER JOIN lift_templates ON lift_templates.workout_template_id = workout_templates.id
      INNER JOIN exercises ON exercises.id = lift_templates.exercise_id
      WHERE workout_templates.template_id = ?
      ORDER BY workout_templates."order" ASC, lift_templates."order" ASC
    `,
    [input.templateId],
  );
  const focusMuscleRows = await client.query<FocusMuscleRow>(
    "SELECT muscle_id FROM template_focus_muscles WHERE template_id = ?",
    [input.templateId],
  );
  const focusMuscleIds = focusMuscleRows.map((row) => row.muscle_id);
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
      const prescription = await buildNextLiftPrescription(client, {
        programId: input.programId,
        programWeek: input.programWeek,
        workoutDay: dayOrder,
        liftRow,
        focusMuscleIds,
        programLengthWeeks: input.programLengthWeeks,
      });
      const manualCheckinStatus: ManualCheckinStatus = prescription.manualCheckinSourceLiftId
        ? "pending"
        : "none";

      await client.run(
        `
          INSERT INTO lifts
            (
              exercise_id,
              workout_id,
              locked,
              hidden,
              "order",
              status,
              planned,
              manual_checkin_status,
              manual_checkin_source_lift_id,
              created_at,
              updated_at
            )
          VALUES (?, ?, 1, 0, ?, 'planned', 1, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `,
        [
          liftRow.exercise_id,
          workoutId,
          liftRow.lift_order,
          manualCheckinStatus,
          prescription.manualCheckinSourceLiftId,
        ],
      );

      const liftId = await loadLastInsertId(client);

      for (const setPlan of prescription.sets) {
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
          [setPlan.plannedReps, setPlan.plannedWeight, setPlan.order, liftId],
        );
      }
    }
  }
}

async function buildNextLiftPrescription(
  client: DatabaseClient,
  input: {
    programId: EntityId;
    programWeek: number;
    workoutDay: number;
    liftRow: TemplateLiftRow;
    focusMuscleIds: EntityId[];
    programLengthWeeks: number;
  },
) {
  const current = await loadLiftHistory(client, {
    programId: input.programId,
    programWeek: input.programWeek - 1,
    workoutDay: input.workoutDay,
    liftOrder: input.liftRow.lift_order,
    exerciseId: input.liftRow.exercise_id,
  });

  if (!current) {
    return buildInitialLiftPrescription();
  }

  const previous = await loadLiftHistory(client, {
    programId: input.programId,
    programWeek: input.programWeek - 2,
    workoutDay: input.workoutDay,
    liftOrder: input.liftRow.lift_order,
    exerciseId: input.liftRow.exercise_id,
  });
  const twoWeeksAgo = await loadLiftHistory(client, {
    programId: input.programId,
    programWeek: input.programWeek - 3,
    workoutDay: input.workoutDay,
    liftOrder: input.liftRow.lift_order,
    exerciseId: input.liftRow.exercise_id,
  });

  return generateNextLiftPrescription({
    current,
    previous,
    twoWeeksAgo,
    exercise: {
      primaryMuscleId: input.liftRow.primary_muscle_id,
      minRepsHypertrophy: input.liftRow.min_reps_hypertrophy,
      maxRepsHypertrophy: input.liftRow.max_reps_hypertrophy,
      repsOnly: Boolean(input.liftRow.reps_only),
    },
    focusMuscleIds: input.focusMuscleIds,
    programLengthWeeks: input.programLengthWeeks,
  });
}

function buildInitialLiftPrescription(): NextLiftPrescription {
  return {
    gate: "gate_7_reps",
    manualCheckinSourceLiftId: null,
    sets: [
      { order: 1, plannedReps: null, plannedWeight: null },
      { order: 2, plannedReps: null, plannedWeight: null },
    ],
  };
}

async function loadLiftHistory(
  client: DatabaseClient,
  input: {
    programId: EntityId;
    programWeek: number;
    workoutDay: number;
    liftOrder: number;
    exerciseId: EntityId;
  },
): Promise<ProgressionLiftHistory | null> {
  if (input.programWeek < 1) {
    return null;
  }

  const liftRows = await client.query<LiftHistoryRow>(
    `
      SELECT
        lifts.id AS lift_id,
        workouts.program_week,
        lifts.status AS lift_status,
        feedback.level_of_pain,
        feedback.level_of_effort,
        lifts.manual_checkin_source_lift_id
      FROM workouts
      INNER JOIN lifts ON lifts.workout_id = workouts.id
      LEFT JOIN feedback ON feedback.lift_id = lifts.id
      WHERE
        workouts.program_id = ?
        AND workouts.program_week = ?
        AND workouts.workout_day = ?
        AND lifts."order" = ?
        AND lifts.exercise_id = ?
      LIMIT 1
    `,
    [input.programId, input.programWeek, input.workoutDay, input.liftOrder, input.exerciseId],
  );
  const lift = liftRows[0];

  if (!lift) {
    return null;
  }

  const setRows = await client.query<LiftHistorySetRow>(
    `
      SELECT
        "order",
        planned_reps,
        planned_weight,
        actual_reps,
        actual_weight,
        status
      FROM workout_sets
      WHERE lift_id = ?
      ORDER BY "order" ASC
    `,
    [lift.lift_id],
  );

  return {
    id: lift.lift_id,
    programWeek: lift.program_week,
    status: mapStatus(lift.lift_status),
    levelOfPain: lift.level_of_pain,
    levelOfEffort: lift.level_of_effort,
    manualCheckinSourceLiftId: lift.manual_checkin_source_lift_id,
    sets: setRows.map(mapProgressionSet),
  };
}

async function loadLastInsertId(client: DatabaseClient): Promise<number> {
  const rows = await client.query<LastInsertIdRow>("SELECT last_insert_rowid() AS id");
  const id = rows[0]?.id;

  if (!id) {
    throw new Error("Failed to load inserted row id.");
  }

  return id;
}
