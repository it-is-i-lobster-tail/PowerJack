import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import type { AppState } from "../../../domain/app-state/AppState";
import { useServices } from "../../../app/useServices";
import "./ActiveWorkoutPage.css";

export function ActiveWorkoutRedirectPage() {
  const services = useServices();
  const navigate = useNavigate();

  useEffect(() => {
    let isMounted = true;

    function navigateFromState(state: AppState | null): void {
      if (!isMounted) {
        return;
      }

      if (!state?.activeProgramId || !state.activeWorkoutId) {
        void navigate("/", { replace: true });
        return;
      }

      void navigate(`/programs/${state.activeProgramId}/workouts/${state.activeWorkoutId}`, {
        replace: true,
      });
    }

    const cachedState = services.cache.getAppStateSnapshot();

    if (cachedState !== undefined) {
      navigateFromState(cachedState);
    } else {
      void services.cache
        .refreshAppState()
        .then(navigateFromState)
        .catch((error: unknown) => {
          console.error("Failed to resume active workout", error);
          if (isMounted) {
            void navigate("/", { replace: true });
          }
        });
    }

    return () => {
      isMounted = false;
    };
  }, [navigate, services.cache]);

  return (
    <main className="app-screen active-workout-screen" data-agent-id="active-workout-redirect-page">
      <section className="active-workout-flow">
        <p className="active-workout-loading">Loading workout</p>
      </section>
    </main>
  );
}
