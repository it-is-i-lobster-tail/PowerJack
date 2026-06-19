import type { EntityId } from "../ids";

export interface AppState {
  id: EntityId;
  activeProgramId: EntityId | null;
  activeWorkoutId: EntityId | null;
  activeLiftId: EntityId | null;
  userBodyWeightLb: number | null;
  userBodyWeightUpdatedLast: string | null;
  createdAt: string;
  updatedAt: string;
}
