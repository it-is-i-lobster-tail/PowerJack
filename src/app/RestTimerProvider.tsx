import { useCallback, useEffect, useMemo, useState, type PropsWithChildren } from "react";
import type { RestTimer } from "../domain/app-state/AppState";
import {
  createCancelledRestTimer,
  createIdleRestTimer,
  createRunningRestTimer,
  normalizeRestTimer,
} from "../domain/app-state/restTimer";
import { RestTimerContext, type StartRestTimerInput } from "./restTimerContext";
import { agentRestTimerResetEventName } from "./restTimerEvents";
import { useServices } from "./useServices";

export function RestTimerProvider({ children }: PropsWithChildren) {
  const services = useServices();
  const [timer, setTimer] = useState<RestTimer>(() => createIdleRestTimer());
  const [isLoaded, setIsLoaded] = useState(false);

  const persistRestTimer = useCallback(
    (nextTimer: RestTimer): void => {
      void services.appState.saveRestTimer(nextTimer).catch((error: unknown) => {
        console.error("Failed to save rest timer", error);
      });
    },
    [services.appState],
  );

  const setAndPersistTimer = useCallback(
    (nextTimer: RestTimer): void => {
      setTimer(nextTimer);
      persistRestTimer(nextTimer);
    },
    [persistRestTimer],
  );

  useEffect(() => {
    let isMounted = true;

    void services.appState
      .load()
      .then((state) => {
        if (!isMounted) {
          return;
        }

        const storedTimer = state?.restTimer ?? createIdleRestTimer();
        const normalizedTimer = normalizeRestTimer(storedTimer);
        setTimer(normalizedTimer);
        setIsLoaded(true);

        if (!areRestTimersEquivalent(storedTimer, normalizedTimer)) {
          persistRestTimer(normalizedTimer);
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load rest timer", error);
        if (isMounted) {
          setTimer(createIdleRestTimer());
          setIsLoaded(true);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [persistRestTimer, services.appState]);

  useEffect(() => {
    function handleAgentReset(): void {
      setTimer(createIdleRestTimer());
    }

    window.addEventListener(agentRestTimerResetEventName, handleAgentReset);

    return () => {
      window.removeEventListener(agentRestTimerResetEventName, handleAgentReset);
    };
  }, []);

  useEffect(() => {
    if (timer.state !== "running") {
      return;
    }

    const intervalId = window.setInterval(() => {
      setTimer((currentTimer) => {
        const normalizedTimer = normalizeRestTimer(currentTimer);

        if (currentTimer.state === "running" && normalizedTimer.state === "expired") {
          persistRestTimer(normalizedTimer);
        }

        return normalizedTimer;
      });
    }, 1000);

    return () => {
      window.clearInterval(intervalId);
    };
  }, [persistRestTimer, timer.state]);

  const startRestTimer = useCallback(
    (input: StartRestTimerInput): void => {
      setAndPersistTimer(
        createRunningRestTimer({
          ...input,
          startedAt: new Date().toISOString(),
        }),
      );
    },
    [setAndPersistTimer],
  );

  const clearRestTimer = useCallback((): void => {
    setAndPersistTimer(createIdleRestTimer());
  }, [setAndPersistTimer]);

  const cancelRestTimer = useCallback((): void => {
    setAndPersistTimer(createCancelledRestTimer());
  }, [setAndPersistTimer]);

  const value = useMemo(
    () => ({
      timer,
      isLoaded,
      startRestTimer,
      clearRestTimer,
      cancelRestTimer,
    }),
    [cancelRestTimer, clearRestTimer, isLoaded, startRestTimer, timer],
  );

  return <RestTimerContext.Provider value={value}>{children}</RestTimerContext.Provider>;
}
function areRestTimersEquivalent(left: RestTimer, right: RestTimer): boolean {
  return (
    left.state === right.state &&
    left.workoutId === right.workoutId &&
    left.liftId === right.liftId &&
    left.nextSetId === right.nextSetId &&
    left.startedAt === right.startedAt &&
    left.durationSeconds === right.durationSeconds &&
    left.remainingSeconds === right.remainingSeconds
  );
}
