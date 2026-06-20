import type { Template, TemplateFocusMuscle, TemplateSummary } from "../../../domain/templates/Template";

export interface TemplateSummaryRow extends Record<string, unknown> {
  id: number;
  name: string;
  workouts_per_week: number;
  exercise_count: number;
  focus_muscles: string | null;
  used_by_active_program: number;
  created_at: string;
  updated_at: string;
}

export interface TemplateRow extends Record<string, unknown> {
  id: number;
  name: string;
  workouts_per_week: number;
  focus_muscle_ids: string | null;
  created_at: string;
  updated_at: string;
}

export function mapTemplateSummaryRow(row: TemplateSummaryRow): TemplateSummary {
  return {
    id: row.id,
    name: row.name,
    workoutsPerWeek: row.workouts_per_week,
    exerciseCount: row.exercise_count,
    focusMuscles: parseFocusMuscles(row.focus_muscles),
    usedByActiveProgram: Boolean(row.used_by_active_program),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapTemplateRow(row: TemplateRow): Template {
  return {
    id: row.id,
    name: row.name,
    workoutsPerWeek: row.workouts_per_week,
    focusMuscleIds: row.focus_muscle_ids
      ? row.focus_muscle_ids.split(",").map((value) => Number(value))
      : [],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function parseFocusMuscles(value: string | null): TemplateFocusMuscle[] {
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
