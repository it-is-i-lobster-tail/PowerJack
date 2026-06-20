import type { ExerciseSummary, Muscle } from "../../../domain/exercises/Exercise";
import type { ExerciseCatalogRepository } from "../../../domain/exercises/ExerciseCatalogRepository";
import type { DatabaseClient } from "../DatabaseClient";
import {
  mapExerciseSummaryRow,
  mapMuscleRow,
  type ExerciseSummaryRow,
  type MuscleRow,
} from "../mappers/exerciseMapper";

export class SqliteExerciseCatalogRepository implements ExerciseCatalogRepository {
  constructor(private readonly db: DatabaseClient) {}

  async listMuscles(): Promise<Muscle[]> {
    const rows = await this.db.query<MuscleRow>("SELECT * FROM muscles ORDER BY name ASC");
    return rows.map(mapMuscleRow);
  }

  async searchExercises(query: string): Promise<ExerciseSummary[]> {
    const normalizedQuery = `%${query.toLowerCase()}%`;
    const rows = await this.db.query<ExerciseSummaryRow>(
      `
        SELECT
          exercises.id,
          exercises.name,
          primary_muscles.name AS primary_muscle_name,
          GROUP_CONCAT(secondary_muscles.name, ',') AS secondary_muscle_names,
          equipment.name AS equipment_name,
          exercises.reps_only,
          exercises.min_reps_hypertrophy,
          exercises.max_reps_hypertrophy
        FROM exercises
        INNER JOIN muscles AS primary_muscles ON primary_muscles.id = exercises.primary_muscle_id
        INNER JOIN equipment ON equipment.id = exercises.equipment_id
        LEFT JOIN exercise_secondary_muscles
          ON exercise_secondary_muscles.exercise_id = exercises.id
        LEFT JOIN muscles AS secondary_muscles
          ON secondary_muscles.id = exercise_secondary_muscles.muscle_id
        WHERE lower(exercises.name) LIKE ?
           OR lower(primary_muscles.name) LIKE ?
           OR lower(equipment.name) LIKE ?
        GROUP BY exercises.id
        ORDER BY exercises.name ASC
        LIMIT 40
      `,
      [normalizedQuery, normalizedQuery, normalizedQuery],
    );

    return rows.map(mapExerciseSummaryRow);
  }
}
