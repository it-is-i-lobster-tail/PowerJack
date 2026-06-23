import type { AppState } from "../../../domain/app-state/AppState";
import { createIdleRestTimer } from "../../../domain/app-state/restTimer";

export interface AppStateRow extends Record<string, unknown> {
  id: number;
  active_program_id: number | null;
  active_workout_id: number | null;
  active_lift_id: number | null;
  rest_timer_state?: string | null;
  rest_timer_workout_id?: number | null;
  rest_timer_lift_id?: number | null;
  rest_timer_next_set_id?: number | null;
  rest_timer_started_at?: string | null;
  rest_timer_duration_seconds?: number | null;
  rest_timer_remaining_seconds?: number | null;
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
    restTimer: {
      ...createIdleRestTimer(),
      state: isRestTimerState(row.rest_timer_state) ? row.rest_timer_state : "idle",
      workoutId: row.rest_timer_workout_id ?? null,
      liftId: row.rest_timer_lift_id ?? null,
      nextSetId: row.rest_timer_next_set_id ?? null,
      startedAt: row.rest_timer_started_at ?? null,
      durationSeconds: row.rest_timer_duration_seconds ?? createIdleRestTimer().durationSeconds,
      remainingSeconds: row.rest_timer_remaining_seconds ?? 0,
    },
    userBodyWeightLb: row.user_body_weight_lb,
    userBodyWeightUpdatedLast: row.user_body_weight_updated_last,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function isRestTimerState(value: unknown): value is AppState["restTimer"]["state"] {
  return value === "idle" || value === "running" || value === "expired" || value === "cancelled";
}
