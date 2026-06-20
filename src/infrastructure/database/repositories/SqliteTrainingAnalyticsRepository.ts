import type { CompletedSetEvent } from "../../../domain/analytics/TrainingAnalytics";
import type { TrainingAnalyticsRepository } from "../../../domain/analytics/TrainingAnalyticsRepository";
import type { EntityId } from "../../../domain/ids";
import type { DatabaseClient } from "../DatabaseClient";

interface CompletedSetEventRow extends Record<string, unknown> {
  set_id: number;
  muscle_id: number;
  muscle_name: string;
  completed_at: string;
}

export class SqliteTrainingAnalyticsRepository implements TrainingAnalyticsRepository {
  constructor(private readonly db: DatabaseClient) {}

  async loadCompletedSetEvents(input: {
    fromInclusive: string;
    toExclusive: string;
  }): Promise<CompletedSetEvent[]> {
    const rows = await this.db.query<CompletedSetEventRow>(
      `
        SELECT
          workout_sets.id AS set_id,
          muscles.id AS muscle_id,
          muscles.name AS muscle_name,
          workout_sets.updated_at AS completed_at
        FROM workout_sets
        INNER JOIN lifts ON lifts.id = workout_sets.lift_id
        INNER JOIN exercises ON exercises.id = lifts.exercise_id
        INNER JOIN muscles ON muscles.id = exercises.primary_muscle_id
        WHERE
          workout_sets.status = 'complete'
          AND workout_sets.actual_reps IS NOT NULL
          AND datetime(workout_sets.updated_at) >= datetime(?)
          AND datetime(workout_sets.updated_at) < datetime(?)
        ORDER BY workout_sets.updated_at ASC, muscles.name ASC
      `,
      [input.fromInclusive, input.toExclusive],
    );

    return rows.map((row) => ({
      setId: row.set_id,
      muscleId: row.muscle_id,
      muscleName: row.muscle_name,
      completedAt: row.completed_at,
    }));
  }

  async loadCompletedSetEventsForProgram(programId: EntityId): Promise<CompletedSetEvent[]> {
    const rows = await this.db.query<CompletedSetEventRow>(
      `
        SELECT
          workout_sets.id AS set_id,
          muscles.id AS muscle_id,
          muscles.name AS muscle_name,
          workout_sets.updated_at AS completed_at
        FROM workout_sets
        INNER JOIN lifts ON lifts.id = workout_sets.lift_id
        INNER JOIN workouts ON workouts.id = lifts.workout_id
        INNER JOIN exercises ON exercises.id = lifts.exercise_id
        INNER JOIN muscles ON muscles.id = exercises.primary_muscle_id
        WHERE
          workouts.program_id = ?
          AND workout_sets.status = 'complete'
          AND workout_sets.actual_reps IS NOT NULL
          AND workout_sets.actual_weight IS NOT NULL
        ORDER BY workout_sets.updated_at ASC, muscles.name ASC
      `,
      [programId],
    );

    return rows.map((row) => ({
      setId: row.set_id,
      muscleId: row.muscle_id,
      muscleName: row.muscle_name,
      completedAt: row.completed_at,
    }));
  }
}
