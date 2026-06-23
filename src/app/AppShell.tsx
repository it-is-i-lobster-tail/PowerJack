import { Menu, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Outlet, useLocation, useNavigate } from "react-router-dom";
import type { AppState } from "../domain/app-state/AppState";
import { formatRestTimerRemaining, shouldDisplayRestTimer } from "../domain/app-state/restTimer";
import type { ActiveWorkoutView } from "../domain/workouts/Workout";
import { findRestTimerTargetBySetId } from "../domain/workouts/restTimerTarget";
import { Button } from "../shared/ui/Button";
import { useRestTimer } from "./useRestTimer";
import { useServices } from "./useServices";
import "./AppShell.css";

export function AppShell() {
  const services = useServices();
  const { cancelRestTimer, clearRestTimer, timer } = useRestTimer();
  const navigate = useNavigate();
  const location = useLocation();
  const menuRef = useRef<HTMLDivElement | null>(null);
  const [appState, setAppState] = useState<AppState | null>(null);
  const [activeWorkoutView, setActiveWorkoutView] = useState<ActiveWorkoutView | null>(null);
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const activeWorkoutPath =
    appState?.activeProgramId && appState.activeWorkoutId
      ? `/programs/${appState.activeProgramId}/workouts/${appState.activeWorkoutId}`
      : null;
  const isViewingActiveWorkout = activeWorkoutPath === location.pathname || location.pathname === "/workouts/active";
  const canResume = Boolean(activeWorkoutPath && !isViewingActiveWorkout);
  const visibleRestTimer = shouldDisplayRestTimer(timer) ? timer : null;
  const resumeTimerTarget =
    visibleRestTimer && activeWorkoutView?.workout.id === visibleRestTimer.workoutId
      ? findRestTimerTargetBySetId(activeWorkoutView, visibleRestTimer.nextSetId)
      : null;

  useEffect(() => {
    let isMounted = true;

    void services.appState.load().then((state) => {
      if (isMounted) {
        setAppState(state);
      }
    });

    return () => {
      isMounted = false;
    };
  }, [location.key, services.appState]);

  useEffect(() => {
    let isMounted = true;

    if (!visibleRestTimer?.workoutId) {
      return () => {
        isMounted = false;
      };
    }

    void services.workouts
      .loadWorkoutView(visibleRestTimer.workoutId)
      .then((view) => {
        if (!isMounted) {
          return;
        }

        setActiveWorkoutView(view);

        if (view && !findRestTimerTargetBySetId(view, visibleRestTimer.nextSetId)) {
          clearRestTimer();
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to load active workout for rest timer", error);
      });

    return () => {
      isMounted = false;
    };
  }, [
    clearRestTimer,
    services.workouts,
    visibleRestTimer?.nextSetId,
    visibleRestTimer?.state,
    visibleRestTimer?.workoutId,
  ]);

  useEffect(() => {
    if (!isMenuOpen) {
      return;
    }

    function handlePointerDown(event: PointerEvent): void {
      if (!menuRef.current?.contains(event.target as Node)) {
        setIsMenuOpen(false);
      }
    }

    function handleKeyDown(event: KeyboardEvent): void {
      if (event.key === "Escape") {
        setIsMenuOpen(false);
      }
    }

    document.addEventListener("pointerdown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [isMenuOpen]);

  function closeMenuAndNavigate(path: string): void {
    setIsMenuOpen(false);
    void navigate(path);
  }

  return (
    <div className="app-shell">
      <header className="app-top-bar" data-agent-id="app-top-bar">
        <div className="app-top-bar__left">
          <img
            alt="PowerJack"
            className="app-top-bar__logo"
            data-agent-id="app-logo"
            src="/assets/power-jack-logo-favicon.png"
          />
        </div>
        <div className="app-top-bar__center">
          {canResume && visibleRestTimer && resumeTimerTarget && activeWorkoutView ? (
            <div className="resume-workout-banner" data-agent-id="resume-workout-banner">
              <button
                className="resume-workout-banner__body"
                data-agent-id="resume-workout"
                onClick={() => {
                  if (activeWorkoutPath) {
                    void navigate(activeWorkoutPath);
                  }
                }}
                type="button"
              >
                <span className="resume-workout-banner__line">
                  <strong>Resume workout</strong>
                  <strong className="resume-workout-banner__timer">
                    {visibleRestTimer.state === "expired"
                      ? "Ready"
                      : `Rest ${formatRestTimerRemaining(visibleRestTimer.remainingSeconds)}`}
                  </strong>
                </span>
                <span className="resume-workout-banner__line resume-workout-banner__line--secondary">
                  <span>Day {activeWorkoutView.workout.workoutDay}</span>
                  <span>
                    {visibleRestTimer.state === "expired"
                      ? resumeTimerTarget.label
                      : `Next: ${resumeTimerTarget.shortLabel}`}
                  </span>
                </span>
              </button>
              <button
                aria-label="Dismiss rest timer"
                className="resume-workout-banner__dismiss"
                data-agent-id="resume-rest-timer-dismiss"
                onClick={cancelRestTimer}
                type="button"
              >
                <X aria-hidden size={16} strokeWidth={2.5} />
              </button>
            </div>
          ) : canResume ? (
            <Button
              className="resume-workout-button"
              data-agent-id="resume-workout"
              onClick={() => {
                if (activeWorkoutPath) {
                  void navigate(activeWorkoutPath);
                }
              }}
              variant="primary"
            >
              Resume workout
            </Button>
          ) : null}
        </div>
        <div className="app-top-bar__actions" ref={menuRef}>
          <button
            aria-expanded={isMenuOpen}
            aria-label="Open app menu"
            className={isMenuOpen ? "app-icon-button app-icon-button--active" : "app-icon-button"}
            data-agent-id="app-menu-toggle"
            onClick={() => setIsMenuOpen((open) => !open)}
            type="button"
          >
            <Menu aria-hidden size={28} strokeWidth={2.3} />
          </button>

          {isMenuOpen ? (
            <nav className="app-menu" data-agent-id="app-menu" aria-label="App menu">
              <button
                data-agent-id="menu-current-program"
                onClick={() =>
                  closeMenuAndNavigate(
                    appState?.activeProgramId ? `/programs/${appState.activeProgramId}` : "/",
                  )
                }
                type="button"
              >
                Current Program
              </button>
              <button
                data-agent-id="menu-data-visualization"
                onClick={() => closeMenuAndNavigate("/visualization")}
                type="button"
              >
                Data Visualization
              </button>
              <button
                data-agent-id="menu-programs"
                onClick={() => closeMenuAndNavigate("/programs")}
                type="button"
              >
                Programs
              </button>
              <button
                data-agent-id="menu-templates"
                onClick={() => closeMenuAndNavigate("/templates")}
                type="button"
              >
                Templates
              </button>
            </nav>
          ) : null}
        </div>
      </header>

      <div className="app-shell__content">
        <Outlet />
      </div>
    </div>
  );
}
