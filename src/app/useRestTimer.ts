import { useContext } from "react";
import { RestTimerContext } from "./restTimerContext";
import type { RestTimerContextValue } from "./restTimerContext";

export function useRestTimer(): RestTimerContextValue {
  const context = useContext(RestTimerContext);

  if (!context) {
    throw new Error("useRestTimer must be used inside RestTimerProvider");
  }

  return context;
}
