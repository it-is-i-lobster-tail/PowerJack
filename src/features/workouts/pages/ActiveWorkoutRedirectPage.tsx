import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { loadStartupState } from "../../../application/app-state/loadStartupState";
import { useServices } from "../../../app/useServices";
import "./ActiveWorkoutPage.css";

export function ActiveWorkoutRedirectPage() {
  const services = useServices();
  const navigate = useNavigate();

  useEffect(() => {
    let isMounted = true;

    void loadStartupState(services.appState)
      .then((state) => {
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
      })
      .catch((error: unknown) => {
        console.error("Failed to resume active workout", error);
        if (isMounted) {
          void navigate("/", { replace: true });
        }
      });

    return () => {
      isMounted = false;
    };
  }, [navigate, services.appState]);

  return (
    <main className="app-screen active-workout-screen" data-agent-id="active-workout-redirect-page">
      <section className="active-workout-flow">
        <p className="active-workout-loading">Loading workout</p>
      </section>
    </main>
  );
}
