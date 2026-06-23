import type { EntityId } from "../ids";
import type { RestTimer, RestTimerState } from "./AppState";

export const defaultRestTimerDurationSeconds = 120;

export const activeRestTimerStates: ReadonlySet<RestTimerState> = new Set(["running", "expired"]);

export function createIdleRestTimer(): RestTimer {
  return createInactiveRestTimer("idle");
}

export function createCancelledRestTimer(): RestTimer {
  return createInactiveRestTimer("cancelled");
}

export function createRunningRestTimer(input: {
  workoutId: EntityId;
  liftId: EntityId;
  nextSetId: EntityId;
  startedAt: string;
  durationSeconds?: number;
}): RestTimer {
  const durationSeconds = input.durationSeconds ?? defaultRestTimerDurationSeconds;

  return {
    state: "running",
    workoutId: input.workoutId,
    liftId: input.liftId,
    nextSetId: input.nextSetId,
    startedAt: input.startedAt,
    durationSeconds,
    remainingSeconds: durationSeconds,
  };
}

export function expireRestTimer(timer: RestTimer): RestTimer {
  if (!timer.workoutId || !timer.liftId || !timer.nextSetId) {
    return createIdleRestTimer();
  }

  return {
    ...timer,
    state: "expired",
    remainingSeconds: 0,
  };
}

export function normalizeRestTimer(timer: RestTimer, now = new Date()): RestTimer {
  if (timer.state !== "running") {
    return timer.state === "expired" ? { ...timer, remainingSeconds: 0 } : timer;
  }

  if (!timer.startedAt || !timer.workoutId || !timer.liftId || !timer.nextSetId) {
    return createIdleRestTimer();
  }

  const elapsedSeconds = Math.max(0, Math.floor((now.getTime() - Date.parse(timer.startedAt)) / 1000));
  const remainingSeconds = Math.max(0, timer.durationSeconds - elapsedSeconds);

  if (remainingSeconds <= 0) {
    return expireRestTimer(timer);
  }

  return {
    ...timer,
    remainingSeconds,
  };
}

export function shouldDisplayRestTimer(timer: RestTimer): boolean {
  return activeRestTimerStates.has(timer.state) && Boolean(timer.workoutId && timer.liftId && timer.nextSetId);
}

export function formatRestTimerRemaining(seconds: number): string {
  const clampedSeconds = Math.max(0, Math.floor(seconds));
  const minutes = Math.floor(clampedSeconds / 60);
  const displaySeconds = clampedSeconds % 60;

  return `${minutes}:${displaySeconds.toString().padStart(2, "0")}`;
}

function createInactiveRestTimer(state: Extract<RestTimerState, "idle" | "cancelled">): RestTimer {
  return {
    state,
    workoutId: null,
    liftId: null,
    nextSetId: null,
    startedAt: null,
    durationSeconds: defaultRestTimerDurationSeconds,
    remainingSeconds: 0,
  };
}
