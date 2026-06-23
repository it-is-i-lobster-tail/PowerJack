import { createContext } from "react";
import type { EntityId } from "../domain/ids";
import type { RestTimer } from "../domain/app-state/AppState";

export interface StartRestTimerInput {
  workoutId: EntityId;
  liftId: EntityId;
  nextSetId: EntityId;
}

export interface RestTimerContextValue {
  timer: RestTimer;
  isLoaded: boolean;
  startRestTimer: (input: StartRestTimerInput) => void;
  clearRestTimer: () => void;
  cancelRestTimer: () => void;
}

export const RestTimerContext = createContext<RestTimerContextValue | null>(null);
