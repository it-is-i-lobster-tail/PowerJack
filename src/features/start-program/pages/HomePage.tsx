import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { loadStartupState } from "../../../application/app-state/loadStartupState";
import type { AppState } from "../../../domain/app-state/AppState";
import { Button } from "../../../shared/ui/Button";
import { useServices } from "../../../app/useServices";
import "./HomePage.css";

export function HomePage() {
  const services = useServices();
  const navigate = useNavigate();
  const [appState, setAppState] = useState<AppState | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let isMounted = true;

    void loadStartupState(services.appState)
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
  }, [services.appState]);

  useEffect(() => {
    if (!isLoading && appState?.activeProgramId && appState.activeWorkoutId) {
      void navigate(`/programs/${appState.activeProgramId}/workouts/${appState.activeWorkoutId}`, {
        replace: true,
      });
    }
  }, [appState, isLoading, navigate]);

  return (
    <main className="app-screen app-screen--centered home-screen" data-agent-id="new-program-page">
      <section className="home-card" aria-labelledby="new-program-title">
        <h1 id="new-program-title">New Program</h1>
        <Button
          aria-label="Start new program"
          className="home-card__start"
          data-agent-id="start-new-program"
          disabled={isLoading}
          fullWidth
          onClick={() => {
            void navigate("/start/select-template");
          }}
          variant="outline"
        >
          Start
        </Button>
      </section>
    </main>
  );
}
