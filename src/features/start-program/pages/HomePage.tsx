import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import type { AppState } from "../../../domain/app-state/AppState";
import { Button } from "../../../shared/ui/Button";
import { useServices } from "../../../app/useServices";
import "./HomePage.css";

export function HomePage() {
  const services = useServices();
  const navigate = useNavigate();
  const cachedAppState = services.cache.getAppStateSnapshot();
  const [appState, setAppState] = useState<AppState | null>(cachedAppState ?? null);
  const [isLoading, setIsLoading] = useState(cachedAppState === undefined);
  const [isPreparingTemplates, setIsPreparingTemplates] = useState(false);

  useEffect(() => {
    let isMounted = true;

    void services.cache
      .refreshAppState()
      .then((state) => {
        if (isMounted) {
          setAppState(state);
        }
      })
      .finally(() => {
        if (isMounted) {
          setIsLoading(false);
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load startup state", error);
      });

    return () => {
      isMounted = false;
    };
  }, [services.cache]);

  useEffect(() => {
    if (!isLoading && appState?.activeProgramId && appState.activeWorkoutId) {
      void navigate(`/programs/${appState.activeProgramId}/workouts/${appState.activeWorkoutId}`, {
        replace: true,
      });
    }
  }, [appState, isLoading, navigate]);

  useEffect(() => {
    if (!isLoading && !appState?.activeProgramId) {
      void services.cache.loadTemplates().catch(() => undefined);
    }
  }, [appState, isLoading, services.cache]);

  async function handleStart(): Promise<void> {
    setIsPreparingTemplates(true);

    try {
      await services.cache.loadTemplates();
    } catch {
      services.cache.invalidateTemplates();
    } finally {
      setIsPreparingTemplates(false);
    }

    void navigate("/start/select-template");
  }

  return (
    <main className="app-screen app-screen--centered home-screen" data-agent-id="new-program-page">
      <section className="home-card" aria-labelledby="new-program-title">
        <h1 id="new-program-title">New program</h1>
        <Button
          aria-label="Start new program"
          className="home-card__start"
          data-agent-id="start-new-program"
          disabled={isLoading || isPreparingTemplates}
          fullWidth
          onClick={() => {
            void handleStart();
          }}
          variant="primary"
        >
          Start
        </Button>
      </section>
    </main>
  );
}
