import { Menu } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Outlet, useLocation, useNavigate } from "react-router-dom";
import type { AppState } from "../domain/app-state/AppState";
import { Button } from "../shared/ui/Button";
import { useStartProgramStore } from "../features/start-program/state/startProgramStore";
import { useServices } from "./useServices";
import "./AppShell.css";

export function AppShell() {
  const services = useServices();
  const navigate = useNavigate();
  const location = useLocation();
  const menuRef = useRef<HTMLDivElement | null>(null);
  const resetProgramDraft = useStartProgramStore((state) => state.reset);
  const [appState, setAppState] = useState<AppState | null>(null);
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const activeWorkoutPath =
    appState?.activeProgramId && appState.activeWorkoutId
      ? `/programs/${appState.activeProgramId}/workouts/${appState.activeWorkoutId}`
      : null;
  const isViewingActiveWorkout = activeWorkoutPath === location.pathname || location.pathname === "/workouts/active";
  const canResume = Boolean(activeWorkoutPath && !isViewingActiveWorkout);

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
        <div className="app-top-bar__left" aria-hidden />
        <div className="app-top-bar__center">
          {canResume ? (
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
                Current program
              </button>
              <button
                data-agent-id="menu-new-program"
                onClick={() => {
                  resetProgramDraft();
                  closeMenuAndNavigate("/start/select-template");
                }}
                type="button"
              >
                New program
              </button>
              <button
                data-agent-id="menu-data-visualization"
                onClick={() => closeMenuAndNavigate("/visualization")}
                type="button"
              >
                Data visualization
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
