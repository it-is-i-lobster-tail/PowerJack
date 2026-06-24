import {
  primaryMuscleSetCredit,
  secondaryMuscleSetCredit,
  type CompletedSetEvent,
} from "../../../domain/analytics/TrainingAnalytics";
import type { TrainingAnalyticsRepository } from "../../../domain/analytics/TrainingAnalyticsRepository";
import type { EntityId } from "../../../domain/ids";
import type { DatabaseClient } from "../DatabaseClient";

interface CompletedSetEventRow extends Record<string, unknown> {
  set_id: number;
  muscle_id: number;
  muscle_name: string;
  completed_at: string;
  set_credit: number;
}

export class SqliteTrainingAnalyticsRepository implements TrainingAnalyticsRepository {
  constructor(private readonly db: DatabaseClient) {}

  async loadCompletedSetEvents(input: {
    fromInclusive: string;
    toExclusive: string;
  }): Promise<CompletedSetEvent[]> {
    const rows = await this.db.query<CompletedSetEventRow>(
      `
        WITH completed_sets AS (
          SELECT
            workout_sets.id AS set_id,
            workout_sets.updated_at AS completed_at,
            exercises.id AS exercise_id,
            exercises.primary_muscle_id AS primary_muscle_id
          FROM workout_sets
          INNER JOIN lifts ON lifts.id = workout_sets.lift_id
          INNER JOIN exercises ON exercises.id = lifts.exercise_id
          WHERE
            workout_sets.status = 'completed'
            AND workout_sets.actual_reps IS NOT NULL
            AND datetime(workout_sets.updated_at) >= datetime(?)
            AND datetime(workout_sets.updated_at) < datetime(?)
        )
        SELECT
          completed_sets.set_id,
          muscles.id AS muscle_id,
          muscles.name AS muscle_name,
          completed_sets.completed_at,
          ? AS set_credit
        FROM completed_sets
        INNER JOIN muscles ON muscles.id = completed_sets.primary_muscle_id
        UNION ALL
        SELECT
          completed_sets.set_id,
          secondary_muscles.id AS muscle_id,
          secondary_muscles.name AS muscle_name,
          completed_sets.completed_at,
          ? AS set_credit
        FROM completed_sets
        INNER JOIN exercise_secondary_muscles
          ON exercise_secondary_muscles.exercise_id = completed_sets.exercise_id
        INNER JOIN muscles AS secondary_muscles
          ON secondary_muscles.id = exercise_secondary_muscles.muscle_id
        ORDER BY completed_at ASC, muscle_name ASC
      `,
      [input.fromInclusive, input.toExclusive, primaryMuscleSetCredit, secondaryMuscleSetCredit],
    );

    return rows.map((row) => ({
      setId: row.set_id,
      muscleId: row.muscle_id,
      muscleName: row.muscle_name,
      completedAt: row.completed_at,
      setCredit: row.set_credit,
    }));
  }

  async loadCompletedSetEventsForProgram(programId: EntityId): Promise<CompletedSetEvent[]> {
    const rows = await this.db.query<CompletedSetEventRow>(
      `
        WITH completed_sets AS (
          SELECT
            workout_sets.id AS set_id,
            workout_sets.updated_at AS completed_at,
            exercises.id AS exercise_id,
            exercises.primary_muscle_id AS primary_muscle_id
          FROM workout_sets
          INNER JOIN lifts ON lifts.id = workout_sets.lift_id
          INNER JOIN workouts ON workouts.id = lifts.workout_id
          INNER JOIN exercises ON exercises.id = lifts.exercise_id
          WHERE
            workouts.program_id = ?
            AND workout_sets.status = 'completed'
            AND workout_sets.actual_reps IS NOT NULL
        )
        SELECT
          completed_sets.set_id,
          muscles.id AS muscle_id,
          muscles.name AS muscle_name,
          completed_sets.completed_at,
          ? AS set_credit
        FROM completed_sets
        INNER JOIN muscles ON muscles.id = completed_sets.primary_muscle_id
        UNION ALL
        SELECT
          completed_sets.set_id,
          secondary_muscles.id AS muscle_id,
          secondary_muscles.name AS muscle_name,
          completed_sets.completed_at,
          ? AS set_credit
        FROM completed_sets
        INNER JOIN exercise_secondary_muscles
          ON exercise_secondary_muscles.exercise_id = completed_sets.exercise_id
        INNER JOIN muscles AS secondary_muscles
          ON secondary_muscles.id = exercise_secondary_muscles.muscle_id
        ORDER BY completed_at ASC, muscle_name ASC
      `,
      [programId, primaryMuscleSetCredit, secondaryMuscleSetCredit],
    );

    return rows.map((row) => ({
      setId: row.set_id,
      muscleId: row.muscle_id,
      muscleName: row.muscle_name,
      completedAt: row.completed_at,
      setCredit: row.set_credit,
    }));
  }
}
