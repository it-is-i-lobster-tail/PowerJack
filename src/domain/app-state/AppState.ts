import type { EntityId } from "../ids";

export type RestTimerState = "idle" | "running" | "expired" | "cancelled";

export interface RestTimer {
  state: RestTimerState;
  workoutId: EntityId | null;
  liftId: EntityId | null;
  nextSetId: EntityId | null;
  startedAt: string | null;
  durationSeconds: number;
  remainingSeconds: number;
}

export interface AppState {
  id: EntityId;
  activeProgramId: EntityId | null;
  activeWorkoutId: EntityId | null;
  activeLiftId: EntityId | null;
  restTimer: RestTimer;
  userBodyWeightLb: number | null;
  userBodyWeightUpdatedLast: string | null;
  createdAt: string;
  updatedAt: string;
}
