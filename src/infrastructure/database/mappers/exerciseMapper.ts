import type { ExerciseSummary, Muscle } from "../../../domain/exercises/Exercise";

export interface MuscleRow extends Record<string, unknown> {
  id: number;
  name: string;
  created_at: string;
  updated_at: string;
}

export interface ExerciseSummaryRow extends Record<string, unknown> {
  id: number;
  name: string;
  primary_muscle_name: string;
  secondary_muscle_names: string | null;
  equipment_name: string;
  min_reps_hypertrophy: number;
  max_reps_hypertrophy: number;
}

export function mapMuscleRow(row: MuscleRow): Muscle {
  return {
    id: row.id,
    name: row.name,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapExerciseSummaryRow(row: ExerciseSummaryRow): ExerciseSummary {
  return {
    id: row.id,
    name: row.name,
    primaryMuscleName: row.primary_muscle_name,
    secondaryMuscleNames: row.secondary_muscle_names
      ? row.secondary_muscle_names.split(",").filter(Boolean)
      : [],
    equipmentName: row.equipment_name,
    minRepsHypertrophy: row.min_reps_hypertrophy,
    maxRepsHypertrophy: row.max_reps_hypertrophy,
  };
}
