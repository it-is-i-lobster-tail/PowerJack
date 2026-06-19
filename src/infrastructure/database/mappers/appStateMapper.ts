import type { AppState } from "../../../domain/app-state/AppState";

export interface AppStateRow extends Record<string, unknown> {
  id: number;
  active_program_id: number | null;
  active_workout_id: number | null;
  active_lift_id: number | null;
  user_body_weight_lb: number | null;
  user_body_weight_updated_last: string | null;
  created_at: string;
  updated_at: string;
}

export function mapAppStateRow(row: AppStateRow): AppState {
  return {
    id: row.id,
    activeProgramId: row.active_program_id,
    activeWorkoutId: row.active_workout_id,
    activeLiftId: row.active_lift_id,
    userBodyWeightLb: row.user_body_weight_lb,
    userBodyWeightUpdatedLast: row.user_body_weight_updated_last,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
