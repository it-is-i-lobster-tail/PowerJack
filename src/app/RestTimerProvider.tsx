import { useCallback, useEffect, useMemo, useRef, useState, type PropsWithChildren } from "react";
import type { RestTimer } from "../domain/app-state/AppState";
import type { AppStateRepository } from "../domain/app-state/AppStateRepository";
import {
  createCancelledRestTimer,
  createIdleRestTimer,
  createRunningRestTimer,
  normalizeRestTimer,
} from "../domain/app-state/restTimer";
import { RestTimerContext, type StartRestTimerInput } from "./restTimerContext";
import { agentRestTimerResetEventName } from "./restTimerEvents";
import { useServices } from "./useServices";

const restTimerPersistRetryDelaysMs = [80, 180, 360];

export function RestTimerProvider({ children }: PropsWithChildren) {
  const services = useServices();
  const persistQueueRef = useRef<Promise<void>>(Promise.resolve());
  const [timer, setTimer] = useState<RestTimer>(() => createIdleRestTimer());
  const [isLoaded, setIsLoaded] = useState(false);

  const persistRestTimer = useCallback(
    (nextTimer: RestTimer): void => {
      const persistPromise = persistQueueRef.current
        .catch(() => undefined)
        .then(() => saveRestTimerWithRetry(services.appState, nextTimer));

      persistQueueRef.current = persistPromise;

      void persistPromise.catch((error: unknown) => {
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

async function saveRestTimerWithRetry(
  repository: AppStateRepository,
  timer: RestTimer,
): Promise<void> {
  for (let attempt = 0; attempt <= restTimerPersistRetryDelaysMs.length; attempt += 1) {
    try {
      await repository.saveRestTimer(timer);
      return;
    } catch (error) {
      const delayMs = restTimerPersistRetryDelaysMs[attempt];

      if (!isWebTransactionBusyError(error) || delayMs === undefined) {
        throw error;
      }

      await wait(delayMs);
    }
  }
}

function isWebTransactionBusyError(error: unknown): boolean {
  return error instanceof Error && /begintransaction|cannot start a transaction/i.test(error.message);
}

function wait(delayMs: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, delayMs));
}
