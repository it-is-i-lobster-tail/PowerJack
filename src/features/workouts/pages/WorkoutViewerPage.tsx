import { Check, ChevronLeft, ChevronRight, LockKeyhole } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { finishWorkout } from "../../../application/workouts/finishWorkout";
import { loadWorkoutView } from "../../../application/workouts/loadWorkoutView";
import { submitLiftFeedback } from "../../../application/workouts/submitLiftFeedback";
import { updateWorkoutSet } from "../../../application/workouts/updateWorkoutSet";
import { useServices } from "../../../app/useServices";
import type {
  ActiveWorkoutLiftView,
  ActiveWorkoutSetView,
  ActiveWorkoutView,
} from "../../../domain/workouts/Workout";
import { Button } from "../../../shared/ui/Button";
import "./ActiveWorkoutPage.css";

interface SetDraftValue {
  reps: string;
  weight: string;
}

type SetDraftValues = Record<number, SetDraftValue>;
type SetPersistTimers = Record<number, ReturnType<typeof window.setTimeout>>;

const setAutosaveDelayMs = 300;
const painFeedbackOptions = [
  { value: 1, label: "None" },
  { value: 2, label: "Mild" },
  { value: 3, label: "Noticeable" },
  { value: 4, label: "Sharp" },
  { value: 5, label: "Stop-level" },
] as const;
const effortFeedbackOptions = [
  { value: 1, label: "Easy" },
  { value: 2, label: "Manageable" },
  { value: 3, label: "Challenging" },
  { value: 4, label: "Very hard" },
  { value: 5, label: "Too much" },
] as const;

interface CommitViewOptions {
  clearPendingPersists?: boolean;
  preservePendingDrafts?: boolean;
}

export function WorkoutViewerPage() {
  const services = useServices();
  const navigate = useNavigate();
  const params = useParams();
  const saveVersionRef = useRef(0);
  const persistTimersRef = useRef<SetPersistTimers>({});
  const draftValuesRef = useRef<SetDraftValues>({});
  const viewRef = useRef<ActiveWorkoutView | null>(null);
  const [view, setView] = useState<ActiveWorkoutView | null>(null);
  const [draftValues, setDraftValues] = useState<SetDraftValues>({});
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [feedbackLift, setFeedbackLift] = useState<ActiveWorkoutLiftView | null>(null);
  const [feedbackPain, setFeedbackPain] = useState<number | null>(null);
  const [feedbackEffort, setFeedbackEffort] = useState<number | null>(null);
  const [feedbackError, setFeedbackError] = useState<string | null>(null);
  const [isFeedbackSaving, setIsFeedbackSaving] = useState(false);

  const clearPendingSetPersists = useCallback(() => {
    for (const timer of Object.values(persistTimersRef.current)) {
      window.clearTimeout(timer);
    }

    persistTimersRef.current = {};
  }, []);

  const commitView = useCallback(
    (nextView: ActiveWorkoutView, options: CommitViewOptions = {}): void => {
      const { clearPendingPersists = true, preservePendingDrafts = false } = options;

      if (clearPendingPersists) {
        clearPendingSetPersists();
      }

      const nextDraftValues = buildDraftValues(nextView);

      if (preservePendingDrafts) {
        for (const setId of Object.keys(persistTimersRef.current)) {
          const numericSetId = Number(setId);
          const pendingDraft = draftValuesRef.current[numericSetId];

          if (pendingDraft) {
            nextDraftValues[numericSetId] = pendingDraft;
          }
        }
      }

      setView(nextView);
      viewRef.current = nextView;
      draftValuesRef.current = nextDraftValues;
      setDraftValues(nextDraftValues);
    },
    [clearPendingSetPersists],
  );

  const resetFeedbackModal = useCallback(() => {
    setFeedbackLift(null);
    setFeedbackPain(null);
    setFeedbackEffort(null);
    setFeedbackError(null);
    setIsFeedbackSaving(false);
  }, []);

  const openFeedbackIfNeeded = useCallback(
    (nextView: ActiveWorkoutView, previousView?: ActiveWorkoutView | null): void => {
      const pendingLift = findPendingFeedbackLift(nextView, previousView);

      if (!pendingLift) {
        return;
      }

      setFeedbackLift(pendingLift);
      setFeedbackPain(null);
      setFeedbackEffort(null);
      setFeedbackError(null);
    },
    [],
  );

  useEffect(() => {
    let isMounted = true;
    const routeWorkoutId = Number(params.workoutId);
    const routeProgramId = Number(params.programId);

    if (!Number.isInteger(routeWorkoutId) || !Number.isInteger(routeProgramId)) {
      void navigate("/", { replace: true });
      return () => {
        isMounted = false;
        clearPendingSetPersists();
      };
    }

    clearPendingSetPersists();

    void loadWorkoutView(routeWorkoutId, services.workouts)
      .then((workoutView) => {
        if (!isMounted) {
          return;
        }

        if (!workoutView) {
          void navigate("/", { replace: true });
          return;
        }

        if (workoutView.program.id !== routeProgramId) {
          void navigate(canonicalWorkoutPath(workoutView), { replace: true });
          return;
        }

        resetFeedbackModal();
        commitView(workoutView);
        openFeedbackIfNeeded(workoutView);
      })
      .catch((error: unknown) => {
        console.error("Failed to load workout", error);
        if (isMounted) {
          setError(error instanceof Error ? error.message : "Could not load workout.");
        }
      })
      .finally(() => {
        if (isMounted) {
          setIsLoading(false);
        }
      });

    return () => {
      isMounted = false;
      clearPendingSetPersists();
    };
  }, [
    clearPendingSetPersists,
    commitView,
    navigate,
    openFeedbackIfNeeded,
    params.programId,
    params.workoutId,
    resetFeedbackModal,
    services.workouts,
  ]);

  function persistSet(setId: number, nextDraft: SetDraftValue): void {
    delete persistTimersRef.current[setId];

    const previousView = viewRef.current;
    const saveVersion = saveVersionRef.current + 1;
    saveVersionRef.current = saveVersion;
    setIsSaving(true);
    setError(null);

    void updateWorkoutSet(
      {
        setId,
        actualReps: toNullableInteger(nextDraft.reps),
        actualWeight: toNullableInteger(nextDraft.weight),
      },
      services.workouts,
    )
      .then((nextView) => {
        if (saveVersionRef.current === saveVersion) {
          commitView(nextView, { clearPendingPersists: false, preservePendingDrafts: true });
          openFeedbackIfNeeded(nextView, previousView);
        }
      })
      .catch((error: unknown) => {
        setError(error instanceof Error ? error.message : "Could not save set.");
      })
      .finally(() => {
        if (saveVersionRef.current === saveVersion) {
          setIsSaving(false);
        }
      });
  }

  function handleSaveFeedback(): void {
    if (!feedbackLift || feedbackPain === null || feedbackEffort === null) {
      return;
    }

    setIsFeedbackSaving(true);
    setFeedbackError(null);
    setError(null);

    void submitLiftFeedback(
      {
        liftId: feedbackLift.id,
        levelOfPain: feedbackPain,
        levelOfEffort: feedbackEffort,
      },
      services.workouts,
    )
      .then((nextView) => {
        commitView(nextView, { clearPendingPersists: false, preservePendingDrafts: true });
        resetFeedbackModal();
        openFeedbackIfNeeded(nextView);
      })
      .catch((error: unknown) => {
        setFeedbackError(error instanceof Error ? error.message : "Could not save feedback.");
      })
      .finally(() => {
        setIsFeedbackSaving(false);
      });
  }

  function scheduleSetPersist(setId: number, nextDraft: SetDraftValue): void {
    const existingTimer = persistTimersRef.current[setId];

    if (existingTimer) {
      window.clearTimeout(existingTimer);
    }

    persistTimersRef.current[setId] = window.setTimeout(() => {
      persistSet(setId, nextDraft);
    }, setAutosaveDelayMs);
  }

  function handleSetFieldChange(setId: number, field: keyof SetDraftValue, value: string): void {
    if (!isAllowedIntegerInput(value)) {
      return;
    }

    const currentDraft = draftValuesRef.current[setId] ?? { reps: "", weight: "" };
    const nextDraft = { ...currentDraft, [field]: value };
    const nextDraftValues = {
      ...draftValuesRef.current,
      [setId]: nextDraft,
    };

    draftValuesRef.current = nextDraftValues;
    setDraftValues(nextDraftValues);
    scheduleSetPersist(setId, nextDraft);
  }

  function handleOpenWorkout(workoutId: number | null): void {
    if (!workoutId || !view) {
      return;
    }

    setError(null);
    clearPendingSetPersists();
    resetFeedbackModal();
    void navigate(`/programs/${view?.program.id}/workouts/${workoutId}`);
  }

  function handleFinishWorkout(): void {
    if (!view?.canFinish) {
      return;
    }

    setIsSaving(true);
    setError(null);

    void finishWorkout(view.workout.id, services.workouts)
      .then((nextView) => {
        if (!nextView) {
          void navigate("/", { replace: true });
          return;
        }

        void navigate(canonicalWorkoutPath(nextView));
      })
      .catch((error: unknown) => {
        setError(error instanceof Error ? error.message : "Could not finish workout.");
      })
      .finally(() => {
        setIsSaving(false);
      });
  }

  if (isLoading && !view) {
    return (
      <main className="app-screen active-workout-screen" data-agent-id="active-workout-page">
        <section className="active-workout-flow">
          <p className="active-workout-loading">Loading workout</p>
        </section>
      </main>
    );
  }

  if (!view) {
    return null;
  }

  return (
    <main className="app-screen active-workout-screen" data-agent-id="active-workout-page">
      <section className="active-workout-flow" aria-labelledby="active-workout-day">
        <header className="workout-header">
          <button
            aria-label="Previous workout"
            className="workout-header__nav"
            data-agent-id="workout-day-prev"
            disabled={!view.previousWorkoutId || isLoading}
            onClick={() => handleOpenWorkout(view.previousWorkoutId)}
            type="button"
          >
            <ChevronLeft aria-hidden size={30} strokeWidth={2.4} />
          </button>

          <div className="workout-header__title">
            <span data-agent-id="workout-week-label">
              Week {view.workout.programWeek}/{view.program.programLengthWeeks}
            </span>
            <h1 data-agent-id="workout-day-title" id="active-workout-day">
              Day {view.workout.workoutDay}
            </h1>
          </div>

          <button
            aria-label="Next workout"
            className="workout-header__nav"
            data-agent-id="workout-day-next"
            disabled={!view.nextWorkoutId || isLoading}
            onClick={() => handleOpenWorkout(view.nextWorkoutId)}
            type="button"
          >
            <ChevronRight aria-hidden size={30} strokeWidth={2.4} />
          </button>
        </header>

        <div className="workout-summary" data-agent-id="workout-set-summary">
          <strong>
            {view.completedSets} of {view.totalSets} sets logged
          </strong>
          {view.isReadOnly ? (
            <span className="workout-summary__state">
              <LockKeyhole aria-hidden size={17} strokeWidth={2.3} />
              Read-only
            </span>
          ) : isSaving ? (
            <span className="workout-summary__state workout-summary__state--saving">Saving</span>
          ) : null}
        </div>

        {error ? (
          <p className="active-workout-error" role="alert">
            {error}
          </p>
        ) : null}

        <div className="lift-stack">
          {view.lifts.map((lift) => (
            <LiftCard
              draftValues={draftValues}
              isReadOnly={view.isReadOnly}
              key={lift.id}
              lift={lift}
              onSetFieldChange={handleSetFieldChange}
            />
          ))}
        </div>

        {view.canFinish ? (
          <div className="finish-workout-panel">
            <Button
              data-agent-id="finish-workout"
              disabled={isSaving}
              fullWidth
              leadingIcon={<Check aria-hidden size={24} strokeWidth={2.6} />}
              onClick={handleFinishWorkout}
              variant="outline"
            >
              Finish Workout
            </Button>
          </div>
        ) : null}
      </section>

      {feedbackLift ? (
        <LiftFeedbackModal
          effortValue={feedbackEffort}
          error={feedbackError}
          isSaving={isFeedbackSaving}
          lift={feedbackLift}
          onEffortChange={setFeedbackEffort}
          onPainChange={setFeedbackPain}
          onSave={handleSaveFeedback}
          painValue={feedbackPain}
        />
      ) : null}
    </main>
  );
}

function canonicalWorkoutPath(view: ActiveWorkoutView): string {
  return `/programs/${view.program.id}/workouts/${view.workout.id}`;
}

function findPendingFeedbackLift(
  nextView: ActiveWorkoutView,
  previousView?: ActiveWorkoutView | null,
): ActiveWorkoutLiftView | null {
  if (nextView.isReadOnly) {
    return null;
  }

  if (previousView) {
    const previousLiftsById = new Map(previousView.lifts.map((lift) => [lift.id, lift]));
    const newlyCompletedLift = nextView.lifts.find((lift) => {
      const previousLift = previousLiftsById.get(lift.id);
      return (
        lift.status === "complete" &&
        !lift.feedbackSubmitted &&
        previousLift?.status !== "complete"
      );
    });

    if (newlyCompletedLift) {
      return newlyCompletedLift;
    }
  }

  return nextView.lifts.find((lift) => lift.status === "complete" && !lift.feedbackSubmitted) ?? null;
}

function LiftFeedbackModal({
  effortValue,
  error,
  isSaving,
  lift,
  onEffortChange,
  onPainChange,
  onSave,
  painValue,
}: {
  effortValue: number | null;
  error: string | null;
  isSaving: boolean;
  lift: ActiveWorkoutLiftView;
  onEffortChange: (value: number) => void;
  onPainChange: (value: number) => void;
  onSave: () => void;
  painValue: number | null;
}) {
  const canSave = painValue !== null && effortValue !== null && !isSaving;

  return (
    <div className="feedback-modal-overlay">
      <section
        aria-labelledby="lift-feedback-title"
        aria-modal="true"
        className="lift-feedback-modal"
        data-agent-id="lift-feedback-modal"
        role="dialog"
      >
        <div className="feedback-modal__header">
          <p>Lift Feedback</p>
          <h2 id="lift-feedback-title">{lift.exerciseName}</h2>
        </div>

        <FeedbackScale
          dataAgentPrefix="feedback-pain-option"
          label="Did you experience any pain during this lift?"
          onChange={onPainChange}
          options={painFeedbackOptions}
          value={painValue}
        />

        <FeedbackScale
          dataAgentPrefix="feedback-effort-option"
          label="How difficult was this lift?"
          onChange={onEffortChange}
          options={effortFeedbackOptions}
          value={effortValue}
        />

        {error ? (
          <p className="feedback-error" data-agent-id="feedback-error" role="alert">
            {error}
          </p>
        ) : null}

        <Button
          data-agent-id="feedback-save"
          disabled={!canSave}
          fullWidth
          leadingIcon={<Check aria-hidden size={22} strokeWidth={2.6} />}
          onClick={onSave}
          variant="outline"
        >
          {isSaving ? "Saving Feedback" : "Save Feedback"}
        </Button>
      </section>
    </div>
  );
}

function FeedbackScale({
  dataAgentPrefix,
  label,
  onChange,
  options,
  value,
}: {
  dataAgentPrefix: string;
  label: string;
  onChange: (value: number) => void;
  options: ReadonlyArray<{ readonly value: number; readonly label: string }>;
  value: number | null;
}) {
  return (
    <fieldset className="feedback-scale">
      <legend>{label}</legend>
      <div className="feedback-scale__options">
        {options.map((option) => (
          <button
            aria-pressed={value === option.value}
            className={
              value === option.value
                ? "feedback-option feedback-option--selected"
                : "feedback-option"
            }
            data-agent-id={`${dataAgentPrefix}-${option.value}`}
            key={option.value}
            onClick={() => onChange(option.value)}
            type="button"
          >
            <span>{option.value}</span>
            {option.label}
          </button>
        ))}
      </div>
    </fieldset>
  );
}

function LiftCard({
  draftValues,
  isReadOnly,
  lift,
  onSetFieldChange,
}: {
  draftValues: SetDraftValues;
  isReadOnly: boolean;
  lift: ActiveWorkoutLiftView;
  onSetFieldChange: (setId: number, field: keyof SetDraftValue, value: string) => void;
}) {
  return (
    <article
      className={lift.status === "complete" ? "lift-card lift-card--complete" : "lift-card"}
      data-agent-id={`lift-card-${lift.id}`}
    >
      <div className="lift-card__header">
        <h2>{lift.exerciseName}</h2>
        <span>{lift.sets.length} sets</span>
      </div>

      <div className="set-list">
        {lift.sets.map((set) => (
          <SetRow
            draftValue={draftValues[set.id] ?? valueFromSet(set)}
            isReadOnly={isReadOnly || set.locked}
            key={set.id}
            onSetFieldChange={onSetFieldChange}
            set={set}
          />
        ))}
      </div>
    </article>
  );
}

function SetRow({
  draftValue,
  isReadOnly,
  onSetFieldChange,
  set,
}: {
  draftValue: SetDraftValue;
  isReadOnly: boolean;
  onSetFieldChange: (setId: number, field: keyof SetDraftValue, value: string) => void;
  set: ActiveWorkoutSetView;
}) {
  const isComplete = set.status === "complete";

  return (
    <div
      className={isComplete ? "set-row set-row--complete" : "set-row"}
      data-agent-id={`set-row-${set.id}`}
    >
      <div className="set-row__set">
        <strong>Set {set.order}</strong>
        {isComplete ? (
          <span className="set-row__logged" data-agent-id={`set-logged-${set.id}`}>
            <Check aria-hidden size={16} strokeWidth={2.5} />
            Logged
          </span>
        ) : null}
      </div>

      <label className="set-row__field">
        <span>Reps</span>
        <input
          aria-label={`Set ${set.order} reps`}
          data-agent-id={`set-reps-${set.id}`}
          disabled={isReadOnly}
          inputMode="numeric"
          onChange={(event) => onSetFieldChange(set.id, "reps", event.currentTarget.value)}
          pattern="[0-9]*"
          placeholder={set.plannedReps?.toString() ?? ""}
          type="text"
          value={draftValue.reps}
        />
      </label>

      <span className="set-row__multiplier">x</span>

      <label className="set-row__field">
        <span>Weight</span>
        <input
          aria-label={`Set ${set.order} weight`}
          data-agent-id={`set-weight-${set.id}`}
          disabled={isReadOnly}
          inputMode="numeric"
          onChange={(event) => onSetFieldChange(set.id, "weight", event.currentTarget.value)}
          pattern="[0-9]*"
          placeholder={set.plannedWeight?.toString() ?? ""}
          type="text"
          value={draftValue.weight}
        />
      </label>
    </div>
  );
}

function buildDraftValues(view: ActiveWorkoutView): SetDraftValues {
  return Object.fromEntries(
    view.lifts.flatMap((lift) => lift.sets.map((set) => [set.id, valueFromSet(set)])),
  );
}

function valueFromSet(set: ActiveWorkoutSetView): SetDraftValue {
  return {
    reps: set.actualReps?.toString() ?? "",
    weight: set.actualWeight?.toString() ?? "",
  };
}

function isAllowedIntegerInput(value: string): boolean {
  return value === "" || /^[1-9]\d*$/.test(value);
}

function toNullableInteger(value: string): number | null {
  return value === "" ? null : Number(value);
}
