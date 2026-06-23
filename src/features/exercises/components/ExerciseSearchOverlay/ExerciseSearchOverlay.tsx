import { X } from "lucide-react";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import type { ExerciseSummary } from "../../../../domain/exercises/Exercise";
import "./ExerciseSearchOverlay.css";

interface ExerciseSearchOverlayProps {
  closeAgentId: string;
  closeLabel: string;
  disabled?: boolean;
  error?: string | null;
  inputAgentId: string;
  onClose: () => void;
  onQueryChange: (value: string) => void;
  onSelectExercise: (exercise: ExerciseSummary) => void;
  query: string;
  resultAgentId: (exerciseId: number) => string;
  results: ExerciseSummary[];
  subtitle?: string;
  title: string;
}

interface VisualViewportBox {
  height: number;
  offsetTop: number;
}

export function ExerciseSearchOverlay({
  closeAgentId,
  closeLabel,
  disabled = false,
  error,
  inputAgentId,
  onClose,
  onQueryChange,
  onSelectExercise,
  query,
  resultAgentId,
  results,
  subtitle,
  title,
}: ExerciseSearchOverlayProps) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  const viewport = useVisualViewportBox();
  const titleId = `${inputAgentId}-title`;
  const subtitleId = subtitle ? `${inputAgentId}-context` : undefined;
  const panelTop = getPanelTop(viewport.height);
  const panelClassName = [
    "exercise-search-overlay__panel",
    viewport.height < 560 ? "exercise-search-overlay__panel--tight" : null,
  ]
    .filter(Boolean)
    .join(" ");
  const overlayStyle = {
    "--exercise-search-overlay-height": `${viewport.height}px`,
    "--exercise-search-panel-top": `${panelTop}px`,
    top: `${viewport.offsetTop}px`,
  } as CSSProperties & Record<"--exercise-search-overlay-height" | "--exercise-search-panel-top", string>;

  usePageScrollLock();

  useEffect(() => {
    const focusTimer = window.setTimeout(() => {
      inputRef.current?.focus({ preventScroll: true });
    }, 0);

    return () => window.clearTimeout(focusTimer);
  }, []);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent): void {
      if (event.key === "Escape" && !disabled) {
        onClose();
      }
    }

    document.addEventListener("keydown", handleKeyDown);

    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [disabled, onClose]);

  return (
    <div className="exercise-search-overlay" data-agent-id="exercise-search-overlay" style={overlayStyle}>
      <section
        aria-describedby={subtitleId}
        aria-labelledby={titleId}
        aria-modal="true"
        className={panelClassName}
        role="dialog"
      >
        <div className="exercise-search-overlay__header">
          <div className="exercise-search-overlay__heading">
            <h2 id={titleId}>{title}</h2>
            {subtitle ? (
              <p className="exercise-search-overlay__context" id={subtitleId}>
                {subtitle}
              </p>
            ) : null}
          </div>
          <button
            aria-label={closeLabel}
            className="exercise-search-overlay__close"
            data-agent-id={closeAgentId}
            disabled={disabled}
            onClick={onClose}
            type="button"
          >
            <X aria-hidden size={22} strokeWidth={2.4} />
          </button>
        </div>

        <label className="exercise-search-overlay__field">
          <span className="exercise-search-overlay__label">Exercise search</span>
          <input
            autoCapitalize="none"
            autoComplete="off"
            autoCorrect="off"
            data-agent-id={inputAgentId}
            disabled={disabled}
            onChange={(event) => onQueryChange(event.currentTarget.value)}
            placeholder="bench press"
            ref={inputRef}
            spellCheck={false}
            type="search"
            value={query}
          />
        </label>

        <div
          className="exercise-search-overlay__results"
          data-agent-id="exercise-search-results"
        >
          {results.map((exercise) => (
            <button
              className="exercise-search-overlay__result"
              data-agent-id={resultAgentId(exercise.id)}
              disabled={disabled}
              key={exercise.id}
              onClick={() => onSelectExercise(exercise)}
              type="button"
            >
              <strong>{exercise.name}</strong>
              <span>
                {exercise.primaryMuscleName} - {exercise.equipmentName}
              </span>
            </button>
          ))}
        </div>

        {error ? (
          <p className="exercise-search-overlay__error" data-agent-id="exercise-search-error" role="alert">
            {error}
          </p>
        ) : null}
      </section>
    </div>
  );
}

function getPanelTop(viewportHeight: number): number {
  if (viewportHeight < 480) {
    return 8;
  }

  if (viewportHeight < 560) {
    return 12;
  }

  return Math.min(48, Math.max(16, Math.round(viewportHeight * 0.08)));
}

function useVisualViewportBox(): VisualViewportBox {
  const [viewport, setViewport] = useState<VisualViewportBox>(() => readVisualViewportBox());

  useEffect(() => {
    const visualViewport = window.visualViewport;

    function syncViewport(): void {
      setViewport(readVisualViewportBox());
    }

    syncViewport();
    visualViewport?.addEventListener("resize", syncViewport);
    visualViewport?.addEventListener("scroll", syncViewport);
    window.addEventListener("resize", syncViewport);

    return () => {
      visualViewport?.removeEventListener("resize", syncViewport);
      visualViewport?.removeEventListener("scroll", syncViewport);
      window.removeEventListener("resize", syncViewport);
    };
  }, []);

  return viewport;
}

function readVisualViewportBox(): VisualViewportBox {
  const visualViewport = window.visualViewport;

  return {
    height: visualViewport?.height ?? window.innerHeight,
    offsetTop: visualViewport?.offsetTop ?? 0,
  };
}

function usePageScrollLock(): void {
  useEffect(() => {
    const scrollY = window.scrollY;
    const bodyStyle = document.body.style;
    const documentStyle = document.documentElement.style;
    const previousBodyOverflow = bodyStyle.overflow;
    const previousBodyPosition = bodyStyle.position;
    const previousBodyTop = bodyStyle.top;
    const previousBodyWidth = bodyStyle.width;
    const previousDocumentOverflow = documentStyle.overflow;

    bodyStyle.overflow = "hidden";
    bodyStyle.position = "fixed";
    bodyStyle.top = `-${scrollY}px`;
    bodyStyle.width = "100%";
    documentStyle.overflow = "hidden";

    return () => {
      bodyStyle.overflow = previousBodyOverflow;
      bodyStyle.position = previousBodyPosition;
      bodyStyle.top = previousBodyTop;
      bodyStyle.width = previousBodyWidth;
      documentStyle.overflow = previousDocumentOverflow;
      window.scrollTo(0, scrollY);
    };
  }, []);
}
