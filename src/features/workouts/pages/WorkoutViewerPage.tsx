import {
  AlertTriangle,
  Check,
  ChevronLeft,
  ChevronRight,
  Minus,
  MoreVertical,
  Plus,
  RefreshCw,
  LockKeyhole,
  X,
} from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { searchExercises } from "../../../application/exercises/searchExercises";
import { addSetToLift } from "../../../application/workouts/addSetToLift";
import { changeLiftExercise } from "../../../application/workouts/changeLiftExercise";
import { finishWorkout } from "../../../application/workouts/finishWorkout";
import { loadWorkoutView } from "../../../application/workouts/loadWorkoutView";
import { removeLastSetFromLift } from "../../../application/workouts/removeLastSetFromLift";
import { resolveManualCheckIn } from "../../../application/workouts/resolveManualCheckIn";
import { submitLiftFeedback } from "../../../application/workouts/submitLiftFeedback";
import { updateWorkoutSet } from "../../../application/workouts/updateWorkoutSet";
import { useServices } from "../../../app/useServices";
import type { ExerciseSummary } from "../../../domain/exercises/Exercise";
import { findFollowingWeightSetIds } from "../../../domain/workouts/rules/propagateFollowingSetWeights";
import type {
  ActiveWorkoutLiftView,
  ActiveWorkoutSetView,
  ActiveWorkoutView,
} from "../../../domain/workouts/Workout";
import type { ManualCheckinDecision } from "../../../domain/workouts/WorkoutRepository";
import { maxWorkingSets } from "../../../domain/workouts/progression/generateNextLiftPrescription";
import { Button } from "../../../shared/ui/Button";
import { ConfirmationModal } from "../../../shared/ui/ConfirmationModal";
import "./ActiveWorkoutPage.css";

interface SetDraftValue {
  reps: string;
  weight: string;
}

type SetDraftValues = Record<number, SetDraftValue>;
type SetDraftField = keyof SetDraftValue;
type SetPersistTimers = Record<number, ReturnType<typeof window.setTimeout>>;
type ManualCheckInStep = "skip" | "reset";

interface PendingSetPersist {
  setId: number;
  draft: SetDraftValue;
}

const setAutosaveDelayMs = 500;
const bodyWeightDisplay = "BW";
const painFeedbackOptions = [
  { value: 1, label: "None" },
  { value: 2, label: "Noticeable" },
  { value: 3, label: "High" },
  { value: 4, label: "Sharp" },
  { value: 5, label: "Pure Evil" },
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
  const persistingSetIdsRef = useRef<Set<number>>(new Set());
  const draftValuesRef = useRef<SetDraftValues>({});
  const viewRef = useRef<ActiveWorkoutView | null>(null);
  const dismissedFeedbackLiftIdsRef = useRef<Set<number>>(new Set());
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
  const [, setDismissedFeedbackLiftIds] = useState<Set<number>>(() => new Set());
  const [finishFeedbackHint, setFinishFeedbackHint] = useState<string | null>(null);
  const [manualCheckInStep, setManualCheckInStep] = useState<ManualCheckInStep>("skip");
  const [manualCheckInError, setManualCheckInError] = useState<string | null>(null);
  const [isManualCheckInSaving, setIsManualCheckInSaving] = useState(false);
  const [openLiftMenuId, setOpenLiftMenuId] = useState<number | null>(null);
  const [exerciseChangeLift, setExerciseChangeLift] = useState<ActiveWorkoutLiftView | null>(null);
  const [exerciseChangeQuery, setExerciseChangeQuery] = useState("");
  const [exerciseChangeResults, setExerciseChangeResults] = useState<ExerciseSummary[]>([]);
  const [pendingExerciseChange, setPendingExerciseChange] = useState<{
    lift: ActiveWorkoutLiftView;
    exercise: ExerciseSummary;
  } | null>(null);
  const [removeSetLift, setRemoveSetLift] = useState<ActiveWorkoutLiftView | null>(null);
  const [isLiftMutationSaving, setIsLiftMutationSaving] = useState(false);
  const [liftMutationError, setLiftMutationError] = useState<string | null>(null);

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
        const preservingSetIds = new Set([
          ...Object.keys(persistTimersRef.current).map(Number),
          ...persistingSetIdsRef.current,
        ]);

        for (const setId of preservingSetIds) {
          const pendingDraft = draftValuesRef.current[setId];

          if (pendingDraft) {
            nextDraftValues[setId] = pendingDraft;
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

  const clearDismissedFeedback = useCallback(() => {
    dismissedFeedbackLiftIdsRef.current = new Set();
    setDismissedFeedbackLiftIds(new Set());
  }, []);

  const resetManualCheckInModal = useCallback(() => {
    setManualCheckInStep("skip");
    setManualCheckInError(null);
    setIsManualCheckInSaving(false);
  }, []);

  const resetLiftEditing = useCallback(() => {
    setOpenLiftMenuId(null);
    setExerciseChangeLift(null);
    setExerciseChangeQuery("");
    setExerciseChangeResults([]);
    setPendingExerciseChange(null);
    setRemoveSetLift(null);
    setIsLiftMutationSaving(false);
    setLiftMutationError(null);
  }, []);

  const openFeedbackIfNeeded = useCallback(
    (nextView: ActiveWorkoutView, previousView?: ActiveWorkoutView | null): void => {
      if (findPendingManualCheckInLift(nextView)) {
        return;
      }

      const pendingLift = findPendingFeedbackLift(
        nextView,
        previousView,
        dismissedFeedbackLiftIdsRef.current,
      );

      if (!pendingLift) {
        return;
      }

      blurActiveSetInputForLift(pendingLift);
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
        resetManualCheckInModal();
        resetLiftEditing();
        clearDismissedFeedback();
        setFinishFeedbackHint(null);
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
    clearDismissedFeedback,
    navigate,
    openFeedbackIfNeeded,
    params.programId,
    params.workoutId,
    resetFeedbackModal,
    resetLiftEditing,
    resetManualCheckInModal,
    services.workouts,
  ]);

  useEffect(() => {
    if (openLiftMenuId === null) {
      return;
    }

    function handlePointerDown(event: MouseEvent | TouchEvent): void {
      if (!(event.target instanceof Element)) {
        return;
      }

      if (!event.target.closest(`[data-lift-menu-root="${openLiftMenuId}"]`)) {
        setOpenLiftMenuId(null);
      }
    }

    function handleKeyDown(event: KeyboardEvent): void {
      if (event.key === "Escape") {
        setOpenLiftMenuId(null);
      }
    }

    document.addEventListener("mousedown", handlePointerDown);
    document.addEventListener("touchstart", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("mousedown", handlePointerDown);
      document.removeEventListener("touchstart", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [openLiftMenuId]);

  useEffect(() => {
    let isMounted = true;
    const normalizedQuery = exerciseChangeQuery.trim();

    if (!exerciseChangeLift || !normalizedQuery) {
      return () => {
        isMounted = false;
      };
    }

    void searchExercises(normalizedQuery, services.exercises)
      .then((items) => {
        if (isMounted) {
          setExerciseChangeResults(items.slice(0, 8));
        }
      })
      .catch((error: unknown) => {
        console.error("Failed to search exercises", error);
        if (isMounted) {
          setLiftMutationError("Exercise search failed. Try again.");
        }
      });

    return () => {
      isMounted = false;
    };
  }, [exerciseChangeLift, exerciseChangeQuery, services.exercises]);

  function persistSet(setId: number, nextDraft: SetDraftValue, changedField: SetDraftField): void {
    if (hasPendingManualCheckIn(viewRef.current)) {
      return;
    }

    delete persistTimersRef.current[setId];

    const previousView = viewRef.current;
    const propagationSetIds = findDebouncedWeightPropagationSetIds(
      previousView,
      setId,
      nextDraft,
      changedField,
    );
    const nextDraftValues = propagationSetIds.length > 0
      ? buildPropagatedDraftValues(previousView, propagationSetIds, nextDraft.weight)
      : draftValuesRef.current;
    const pendingPersists: PendingSetPersist[] = [
      { setId, draft: nextDraft },
      ...propagationSetIds.flatMap((propagationSetId) => {
        const propagatedDraft = nextDraftValues[propagationSetId];
        return propagatedDraft ? [{ setId: propagationSetId, draft: propagatedDraft }] : [];
      }),
    ];
    const pendingSetIds = pendingPersists.map((persist) => persist.setId);

    for (const propagationSetId of propagationSetIds) {
      const existingTimer = persistTimersRef.current[propagationSetId];

      if (existingTimer) {
        window.clearTimeout(existingTimer);
        delete persistTimersRef.current[propagationSetId];
      }
    }

    for (const pendingSetId of pendingSetIds) {
      persistingSetIdsRef.current.add(pendingSetId);
    }

    if (nextDraftValues !== draftValuesRef.current) {
      draftValuesRef.current = nextDraftValues;
      setDraftValues(nextDraftValues);
    }

    const saveVersion = saveVersionRef.current + 1;
    saveVersionRef.current = saveVersion;
    setIsSaving(true);
    setError(null);

    void persistSetDrafts(pendingPersists, previousView)
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
        for (const pendingSetId of pendingSetIds) {
          persistingSetIdsRef.current.delete(pendingSetId);
        }

        if (saveVersionRef.current === saveVersion) {
          setIsSaving(false);
        }
      });
  }

  async function persistSetDrafts(
    pendingPersists: readonly PendingSetPersist[],
    previousView: ActiveWorkoutView | null,
  ): Promise<ActiveWorkoutView> {
    let nextView: ActiveWorkoutView | null = null;

    for (const pendingPersist of pendingPersists) {
      nextView = await updateWorkoutSet(
        {
          setId: pendingPersist.setId,
          actualReps: toNullableInteger(pendingPersist.draft.reps),
          actualWeight:
            previousView && isRepsOnlySet(previousView, pendingPersist.setId)
              ? null
              : toNullableInteger(pendingPersist.draft.weight),
        },
        services.workouts,
      );
    }

    if (!nextView) {
      throw new Error("Could not save set.");
    }

    return nextView;
  }

  function findDebouncedWeightPropagationSetIds(
    previousView: ActiveWorkoutView | null,
    setId: number,
    nextDraft: SetDraftValue,
    changedField: SetDraftField,
  ): number[] {
    if (changedField !== "weight" || !previousView) {
      return [];
    }

    const liftAndSet = findLiftAndSet(previousView, setId);

    if (
      !liftAndSet ||
      liftAndSet.lift.repsOnly ||
      !isSetEditable(previousView, liftAndSet.lift, liftAndSet.set)
    ) {
      return [];
    }

    return findFollowingWeightSetIds({
      sets: liftAndSet.lift.sets
        .filter((set) => isSetEditable(previousView, liftAndSet.lift, set))
        .map((set) => ({
          id: set.id,
          order: set.order,
        })),
      editedSetId: setId,
      nextWeight: nextDraft.weight,
    });
  }

  function buildPropagatedDraftValues(
    previousView: ActiveWorkoutView | null,
    propagationSetIds: readonly number[],
    nextWeight: string,
  ): SetDraftValues {
    if (!previousView) {
      return draftValuesRef.current;
    }

    const nextDraftValues = { ...draftValuesRef.current };

    for (const propagationSetId of propagationSetIds) {
      const propagatedSet = findLiftAndSet(previousView, propagationSetId)?.set;

      if (!propagatedSet) {
        continue;
      }

      const propagatedDraft = nextDraftValues[propagationSetId] ?? valueFromSet(propagatedSet);
      nextDraftValues[propagationSetId] = { ...propagatedDraft, weight: nextWeight };
    }

    return nextDraftValues;
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
        markFeedbackLiftAvailable(feedbackLift.id);
        commitView(nextView, { clearPendingPersists: false, preservePendingDrafts: true });
        resetFeedbackModal();
        if (!findFirstLiftNeedingFeedback(nextView)) {
          setFinishFeedbackHint(null);
        }
        openFeedbackIfNeeded(nextView);
      })
      .catch((error: unknown) => {
        setFeedbackError(error instanceof Error ? error.message : "Could not save feedback.");
      })
      .finally(() => {
        setIsFeedbackSaving(false);
      });
  }

  function handleDismissFeedbackModal(): void {
    if (!feedbackLift) {
      return;
    }

    const nextDismissedIds = new Set(dismissedFeedbackLiftIdsRef.current);
    nextDismissedIds.add(feedbackLift.id);
    dismissedFeedbackLiftIdsRef.current = nextDismissedIds;
    setDismissedFeedbackLiftIds(nextDismissedIds);
    resetFeedbackModal();
  }

  function markFeedbackLiftAvailable(liftId: number): void {
    if (!dismissedFeedbackLiftIdsRef.current.has(liftId)) {
      return;
    }

    const nextDismissedIds = new Set(dismissedFeedbackLiftIdsRef.current);
    nextDismissedIds.delete(liftId);
    dismissedFeedbackLiftIdsRef.current = nextDismissedIds;
    setDismissedFeedbackLiftIds(nextDismissedIds);
  }

  function handleOpenFeedbackNeeded(lift: ActiveWorkoutLiftView): void {
    if (lift.status !== "complete" || lift.feedbackSubmitted) {
      return;
    }

    markFeedbackLiftAvailable(lift.id);
    blurActiveSetInputForLift(lift);
    setFeedbackLift(lift);
    setFeedbackPain(null);
    setFeedbackEffort(null);
    setFeedbackError(null);
  }

  function scheduleSetPersist(setId: number, nextDraft: SetDraftValue, changedField: SetDraftField): void {
    const existingTimer = persistTimersRef.current[setId];

    if (existingTimer) {
      window.clearTimeout(existingTimer);
    }

    persistTimersRef.current[setId] = window.setTimeout(() => {
      persistSet(setId, nextDraft, changedField);
    }, setAutosaveDelayMs);
  }

  function handleSetFieldChange(setId: number, field: SetDraftField, value: string): void {
    if (feedbackLift) {
      return;
    }

    if (hasPendingManualCheckIn(viewRef.current)) {
      return;
    }

    if (!isAllowedIntegerInput(value)) {
      return;
    }

    const currentView = viewRef.current;
    const liftAndSet = currentView ? findLiftAndSet(currentView, setId) : null;

    if (!currentView || !liftAndSet || !isSetEditable(currentView, liftAndSet.lift, liftAndSet.set)) {
      return;
    }

    if (field === "weight" && liftAndSet.lift.repsOnly) {
      return;
    }

    const currentDraft =
      draftValuesRef.current[setId] ??
      valueFromSet(liftAndSet.set, {
        prefillPlannedWeight: canUsePlannedWeightAsDraft(currentView, liftAndSet.lift, liftAndSet.set),
      });
    const nextDraft = { ...currentDraft, [field]: value };
    const nextDraftValues = {
      ...draftValuesRef.current,
      [setId]: nextDraft,
    };

    draftValuesRef.current = nextDraftValues;
    setDraftValues(nextDraftValues);
    setFinishFeedbackHint(null);
    scheduleSetPersist(setId, nextDraft, field);
  }

  function handleOpenWorkout(workoutId: number | null): void {
    if (!workoutId || !view || hasPendingManualCheckIn(view)) {
      return;
    }

    setError(null);
    clearPendingSetPersists();
    resetFeedbackModal();
    resetManualCheckInModal();
    resetLiftEditing();
    clearDismissedFeedback();
    setFinishFeedbackHint(null);
    void navigate(`/programs/${view?.program.id}/workouts/${workoutId}`);
  }

  function handleResolveManualCheckIn(decision: ManualCheckinDecision): void {
    const pendingLift = view ? findPendingManualCheckInLift(view) : null;

    if (!pendingLift) {
      return;
    }

    setIsManualCheckInSaving(true);
    setManualCheckInError(null);
    setError(null);
    clearPendingSetPersists();

    void resolveManualCheckIn({ liftId: pendingLift.id, decision }, services.workouts)
      .then((nextView) => {
        commitView(nextView);
        resetManualCheckInModal();
        openFeedbackIfNeeded(nextView);
      })
      .catch((error: unknown) => {
        setManualCheckInError(error instanceof Error ? error.message : "Could not save check-in.");
      })
      .finally(() => {
        setIsManualCheckInSaving(false);
      });
  }

  function handleToggleLiftMenu(lift: ActiveWorkoutLiftView): void {
    if (!canEditLiftInView(viewRef.current, lift) || feedbackLift || isLiftMutationSaving) {
      return;
    }

    setLiftMutationError(null);
    setOpenLiftMenuId((currentId) => (currentId === lift.id ? null : lift.id));
  }

  function handleOpenExerciseChange(lift: ActiveWorkoutLiftView): void {
    if (!canEditLiftInView(viewRef.current, lift) || feedbackLift || isLiftMutationSaving) {
      return;
    }

    setLiftMutationError(null);
    setOpenLiftMenuId(null);
    setExerciseChangeLift(lift);
    setExerciseChangeQuery("");
    setExerciseChangeResults([]);
  }

  function handleAddSet(lift: ActiveWorkoutLiftView): void {
    if (
      !canEditLiftInView(viewRef.current, lift) ||
      feedbackLift ||
      isLiftMutationSaving ||
      lift.sets.length >= maxWorkingSets
    ) {
      return;
    }

    setIsLiftMutationSaving(true);
    setLiftMutationError(null);
    setOpenLiftMenuId(null);
    clearPendingSetPersists();

    void addSetToLift({ liftId: lift.id }, services.workouts)
      .then((nextView) => {
        commitView(nextView);
        openFeedbackIfNeeded(nextView);
      })
      .catch((error: unknown) => {
        console.error("Failed to add set", error);
        setLiftMutationError(error instanceof Error ? error.message : "Could not add set.");
      })
      .finally(() => {
        setIsLiftMutationSaving(false);
      });
  }

  function handleRemoveLastSet(lift: ActiveWorkoutLiftView): void {
    if (
      !canEditLiftInView(viewRef.current, lift) ||
      feedbackLift ||
      isLiftMutationSaving ||
      lift.sets.length <= 1
    ) {
      return;
    }

    setLiftMutationError(null);
    setOpenLiftMenuId(null);

    if (hasLoggedSetValue(lift.sets[lift.sets.length - 1])) {
      setRemoveSetLift(lift);
      return;
    }

    executeRemoveLastSet(lift);
  }

  function executeRemoveLastSet(lift: ActiveWorkoutLiftView): void {
    if (isLiftMutationSaving) {
      return;
    }

    setIsLiftMutationSaving(true);
    setLiftMutationError(null);
    setRemoveSetLift(null);
    clearPendingSetPersists();

    void removeLastSetFromLift({ liftId: lift.id }, services.workouts)
      .then((nextView) => {
        commitView(nextView);
        openFeedbackIfNeeded(nextView);
      })
      .catch((error: unknown) => {
        console.error("Failed to remove set", error);
        setLiftMutationError(error instanceof Error ? error.message : "Could not remove set.");
      })
      .finally(() => {
        setIsLiftMutationSaving(false);
      });
  }

  function handleSelectReplacementExercise(exercise: ExerciseSummary): void {
    if (!exerciseChangeLift || !canEditLiftInView(viewRef.current, exerciseChangeLift)) {
      return;
    }

    if (exercise.id === exerciseChangeLift.exerciseId) {
      setExerciseChangeLift(null);
      setExerciseChangeQuery("");
      setExerciseChangeResults([]);
      return;
    }

    setLiftMutationError(null);

    if (hasLiftLoggedWork(exerciseChangeLift)) {
      setPendingExerciseChange({ lift: exerciseChangeLift, exercise });
      return;
    }

    executeChangeExercise(exerciseChangeLift, exercise);
  }

  function executeChangeExercise(lift: ActiveWorkoutLiftView, exercise: ExerciseSummary): void {
    if (isLiftMutationSaving) {
      return;
    }

    setIsLiftMutationSaving(true);
    setLiftMutationError(null);
    setPendingExerciseChange(null);
    clearPendingSetPersists();

    void changeLiftExercise({ liftId: lift.id, exerciseId: exercise.id }, services.workouts)
      .then((nextView) => {
        commitView(nextView);
        setExerciseChangeLift(null);
        setExerciseChangeQuery("");
        setExerciseChangeResults([]);
        clearDismissedFeedback();
        openFeedbackIfNeeded(nextView);
      })
      .catch((error: unknown) => {
        console.error("Failed to change exercise", error);
        setLiftMutationError(error instanceof Error ? error.message : "Could not change exercise.");
      })
      .finally(() => {
        setIsLiftMutationSaving(false);
      });
  }

  function handleFinishWorkout(): void {
    if (!view) {
      return;
    }

    if (findFirstLiftNeedingFeedback(view)) {
      setFinishFeedbackHint("Complete lift feedback before finishing.");
      return;
    }

    if (!view.canFinish) {
      return;
    }

    setIsSaving(true);
    setError(null);
    setFinishFeedbackHint(null);

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

  const pendingManualCheckInLift = findPendingManualCheckInLift(view);
  const pendingFeedbackLift = findFirstLiftNeedingFeedback(view);
  const isWorkoutWorkComplete = isWorkoutWorkCompleteWithoutFeedback(view);
  const shouldShowFinishWorkout = isWorkoutWorkComplete;
  const isFinishBlockedByFeedback = Boolean(pendingFeedbackLift);
  const finishFeedbackHintId = "finish-feedback-hint";

  return (
    <main className="app-screen active-workout-screen" data-agent-id="active-workout-page">
      <section className="active-workout-flow" aria-labelledby="active-workout-day">
        <header className="workout-header">
          <button
            aria-label="Previous workout"
            className="workout-header__nav"
            data-agent-id="workout-day-prev"
            disabled={!view.previousWorkoutId || isLoading || Boolean(pendingManualCheckInLift)}
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
            disabled={!view.nextWorkoutId || isLoading || Boolean(pendingManualCheckInLift)}
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
        {liftMutationError ? (
          <p className="active-workout-error" data-agent-id="lift-edit-error" role="alert">
            {liftMutationError}
          </p>
        ) : null}

        <div className="lift-stack">
          {view.lifts.map((lift) => (
            <LiftCard
              draftValues={draftValues}
              isLiftMutationSaving={isLiftMutationSaving}
              isMenuOpen={openLiftMenuId === lift.id}
              isReadOnly={view.isReadOnly || Boolean(feedbackLift)}
              key={lift.id}
              lift={lift}
              onAddSet={handleAddSet}
              onChangeExercise={handleOpenExerciseChange}
              onFeedbackNeeded={handleOpenFeedbackNeeded}
              onRemoveLastSet={handleRemoveLastSet}
              onSetFieldChange={handleSetFieldChange}
              onToggleMenu={handleToggleLiftMenu}
              showFeedbackNeeded={
                !feedbackLift && !view.isReadOnly && lift.status === "complete" && !lift.feedbackSubmitted
              }
            />
          ))}
        </div>

        {shouldShowFinishWorkout ? (
          <div className="finish-workout-panel">
            {finishFeedbackHint ? (
              <p
                className="active-workout-warning"
                data-agent-id="finish-feedback-hint"
                id={finishFeedbackHintId}
                role="status"
              >
                <AlertTriangle aria-hidden size={18} strokeWidth={2.4} />
                {finishFeedbackHint}
              </p>
            ) : null}
            <Button
              aria-describedby={finishFeedbackHint ? finishFeedbackHintId : undefined}
              aria-disabled={isFinishBlockedByFeedback || undefined}
              className={isFinishBlockedByFeedback ? "button--soft-disabled" : ""}
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
          onClose={handleDismissFeedbackModal}
          onEffortChange={setFeedbackEffort}
          onPainChange={setFeedbackPain}
          onSave={handleSaveFeedback}
          painValue={feedbackPain}
        />
      ) : null}

      {pendingManualCheckInLift ? (
        <ManualCheckInModal
          error={manualCheckInError}
          isSaving={isManualCheckInSaving}
          lift={pendingManualCheckInLift}
          onContinue={() => handleResolveManualCheckIn("continue")}
          onReset={() => handleResolveManualCheckIn("reset")}
          onSkip={() => handleResolveManualCheckIn("skip")}
          onSkipDecline={() => {
            setManualCheckInError(null);
            setManualCheckInStep("reset");
          }}
          step={manualCheckInStep}
        />
      ) : null}

      {exerciseChangeLift ? (
        <ExerciseChangeModal
          error={liftMutationError}
          isSaving={isLiftMutationSaving}
          lift={exerciseChangeLift}
          onClose={() => {
            setExerciseChangeLift(null);
            setExerciseChangeQuery("");
            setExerciseChangeResults([]);
            setPendingExerciseChange(null);
            setLiftMutationError(null);
          }}
          onQueryChange={(value) => {
            setExerciseChangeQuery(value);
            setLiftMutationError(null);

            if (!value.trim()) {
              setExerciseChangeResults([]);
            }
          }}
          onSelectExercise={handleSelectReplacementExercise}
          query={exerciseChangeQuery}
          results={exerciseChangeResults}
        />
      ) : null}

      {removeSetLift ? (
        <ConfirmationModal
          agentId="remove-last-set-confirmation"
          body={`Remove the last set from ${removeSetLift.exerciseName}? Logged reps and weight on that set will be deleted.`}
          cancelLabel="Back"
          confirmAgentId="modal-delete"
          confirmLabel={isLiftMutationSaving ? "Removing" : "Remove"}
          destructive
          onCancel={() => {
            if (!isLiftMutationSaving) {
              setRemoveSetLift(null);
            }
          }}
          onConfirm={() => executeRemoveLastSet(removeSetLift)}
          title="Remove Last Set"
        />
      ) : null}

      {pendingExerciseChange ? (
        <ConfirmationModal
          agentId="change-exercise-confirmation"
          body={`Change ${pendingExerciseChange.lift.exerciseName} to ${pendingExerciseChange.exercise.name}? This resets progression and set entries for this lift.`}
          cancelLabel="Back"
          confirmLabel={isLiftMutationSaving ? "Changing" : "Change"}
          onCancel={() => {
            if (!isLiftMutationSaving) {
              setPendingExerciseChange(null);
            }
          }}
          onConfirm={() => executeChangeExercise(pendingExerciseChange.lift, pendingExerciseChange.exercise)}
          title="Change Exercise"
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
  dismissedLiftIds: ReadonlySet<number> = new Set(),
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
        !dismissedLiftIds.has(lift.id) &&
        previousLift?.status !== "complete"
      );
    });

    if (newlyCompletedLift) {
      return newlyCompletedLift;
    }
  }

  return (
    nextView.lifts.find(
      (lift) => lift.status === "complete" && !lift.feedbackSubmitted && !dismissedLiftIds.has(lift.id),
    ) ?? null
  );
}

function findFirstLiftNeedingFeedback(view: ActiveWorkoutView): ActiveWorkoutLiftView | null {
  if (view.isReadOnly) {
    return null;
  }

  return view.lifts.find((lift) => lift.status === "complete" && !lift.feedbackSubmitted) ?? null;
}

function isWorkoutWorkCompleteWithoutFeedback(view: ActiveWorkoutView): boolean {
  if (view.isReadOnly || view.lifts.length === 0) {
    return false;
  }

  const countableSets = view.lifts.flatMap((lift) => lift.sets).filter((set) => set.status !== "skipped");
  const allCountableSetsComplete = countableSets.every((set) => set.status === "complete");
  const allLiftsCompleteOrSkipped = view.lifts.every(
    (lift) => lift.status === "complete" || lift.status === "skipped",
  );

  return allCountableSetsComplete && allLiftsCompleteOrSkipped;
}

function findPendingManualCheckInLift(view: ActiveWorkoutView): ActiveWorkoutLiftView | null {
  if (view.isReadOnly) {
    return null;
  }

  return view.lifts.find((lift) => lift.manualCheckinStatus === "pending") ?? null;
}

function hasPendingManualCheckIn(view: ActiveWorkoutView | null): boolean {
  return view ? Boolean(findPendingManualCheckInLift(view)) : false;
}

function canEditLiftInView(view: ActiveWorkoutView | null, lift: ActiveWorkoutLiftView): boolean {
  if (!view || view.isReadOnly || hasPendingManualCheckIn(view) || lift.locked || lift.status === "skipped") {
    return false;
  }

  return view.lifts.some((viewLift) => viewLift.id === lift.id);
}

function hasLoggedSetValue(set: ActiveWorkoutSetView | undefined): boolean {
  return Boolean(set && (set.actualReps !== null || set.actualWeight !== null));
}

function hasLiftLoggedWork(lift: ActiveWorkoutLiftView): boolean {
  return lift.feedbackSubmitted || lift.sets.some(hasLoggedSetValue);
}

function blurActiveSetInputForLift(lift: ActiveWorkoutLiftView): void {
  const activeElement = document.activeElement;

  if (!(activeElement instanceof HTMLInputElement)) {
    return;
  }

  const activeAgentId = activeElement.dataset.agentId;
  const isLiftSetInput = lift.sets.some(
    (set) => activeAgentId === `set-reps-${set.id}` || activeAgentId === `set-weight-${set.id}`,
  );

  if (isLiftSetInput) {
    activeElement.blur();
  }
}

function ManualCheckInModal({
  error,
  isSaving,
  lift,
  onContinue,
  onReset,
  onSkip,
  onSkipDecline,
  step,
}: {
  error: string | null;
  isSaving: boolean;
  lift: ActiveWorkoutLiftView;
  onContinue: () => void;
  onReset: () => void;
  onSkip: () => void;
  onSkipDecline: () => void;
  step: ManualCheckInStep;
}) {
  const painLevel = lift.manualCheckinSourcePain ?? "?";

  return (
    <div className="feedback-modal-overlay">
      <section
        aria-labelledby="manual-checkin-title"
        aria-modal="true"
        className="manual-checkin-modal"
        data-agent-id="manual-checkin-modal"
        role="dialog"
      >
        <div className="feedback-modal__header">
          <p>Manual Check-in</p>
          <h2 id="manual-checkin-title">{lift.exerciseName}</h2>
        </div>

        {step === "skip" ? (
          <>
            <p className="manual-checkin-modal__body">
              Last week {lift.exerciseName} caused a pain of {painLevel}/5. Would you like to skip
              that lift this week?
            </p>
            <div className="manual-checkin-modal__actions">
              <Button
                data-agent-id="manual-checkin-skip-no"
                disabled={isSaving}
                onClick={onSkipDecline}
                variant="secondary"
              >
                No
              </Button>
              <Button
                data-agent-id="manual-checkin-skip-yes"
                disabled={isSaving}
                onClick={onSkip}
                variant="danger"
              >
                {isSaving ? "Saving" : "Yes"}
              </Button>
            </div>
          </>
        ) : (
          <>
            <p className="manual-checkin-modal__body">
              Would you like to reset progress for {lift.exerciseName}? This is recommended.
            </p>
            <div className="manual-checkin-modal__actions">
              <Button
                data-agent-id="manual-checkin-reset-no"
                disabled={isSaving}
                onClick={onContinue}
                variant="secondary"
              >
                No
              </Button>
              <Button
                data-agent-id="manual-checkin-reset-yes"
                disabled={isSaving}
                onClick={onReset}
                variant="outline"
              >
                {isSaving ? "Saving" : "Yes"}
              </Button>
            </div>
          </>
        )}

        {error ? (
          <p className="feedback-error" data-agent-id="manual-checkin-error" role="alert">
            {error}
          </p>
        ) : null}
      </section>
    </div>
  );
}

function LiftFeedbackModal({
  effortValue,
  error,
  isSaving,
  lift,
  onClose,
  onEffortChange,
  onPainChange,
  onSave,
  painValue,
}: {
  effortValue: number | null;
  error: string | null;
  isSaving: boolean;
  lift: ActiveWorkoutLiftView;
  onClose: () => void;
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
        <div className="feedback-modal__header feedback-modal__header--with-close">
          <div>
            <p>Lift Feedback</p>
            <h2 id="lift-feedback-title">{lift.exerciseName}</h2>
          </div>
          <button
            aria-label="Close feedback"
            className="feedback-modal__close"
            data-agent-id="feedback-close"
            disabled={isSaving}
            onClick={onClose}
            type="button"
          >
            <X aria-hidden size={20} strokeWidth={2.4} />
          </button>
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

function ExerciseChangeModal({
  error,
  isSaving,
  lift,
  onClose,
  onQueryChange,
  onSelectExercise,
  query,
  results,
}: {
  error: string | null;
  isSaving: boolean;
  lift: ActiveWorkoutLiftView;
  onClose: () => void;
  onQueryChange: (value: string) => void;
  onSelectExercise: (exercise: ExerciseSummary) => void;
  query: string;
  results: ExerciseSummary[];
}) {
  return (
    <div className="feedback-modal-overlay">
      <section
        aria-labelledby="change-exercise-title"
        aria-modal="true"
        className="exercise-change-modal"
        data-agent-id="change-exercise-modal"
        role="dialog"
      >
        <div className="feedback-modal__header feedback-modal__header--with-close">
          <div>
            <p>Change Exercise</p>
            <h2 id="change-exercise-title">{lift.exerciseName}</h2>
          </div>
          <button
            aria-label="Close exercise change"
            className="feedback-modal__close"
            data-agent-id="change-exercise-close"
            disabled={isSaving}
            onClick={onClose}
            type="button"
          >
            <X aria-hidden size={20} strokeWidth={2.4} />
          </button>
        </div>

        <label className="exercise-change-search">
          <span>Exercise search</span>
          <input
            autoFocus
            data-agent-id="change-exercise-search-input"
            disabled={isSaving}
            onChange={(event) => onQueryChange(event.currentTarget.value)}
            placeholder="bench press"
            value={query}
          />
        </label>

        <div className="exercise-change-results">
          {results.map((exercise) => (
            <button
              className="exercise-change-result"
              data-agent-id={`change-exercise-result-${exercise.id}`}
              disabled={isSaving}
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
          <p className="feedback-error" data-agent-id="change-exercise-error" role="alert">
            {error}
          </p>
        ) : null}
      </section>
    </div>
  );
}

function LiftCard({
  draftValues,
  isLiftMutationSaving,
  isMenuOpen,
  isReadOnly,
  lift,
  onAddSet,
  onChangeExercise,
  onFeedbackNeeded,
  onRemoveLastSet,
  onSetFieldChange,
  onToggleMenu,
  showFeedbackNeeded,
}: {
  draftValues: SetDraftValues;
  isLiftMutationSaving: boolean;
  isMenuOpen: boolean;
  isReadOnly: boolean;
  lift: ActiveWorkoutLiftView;
  onAddSet: (lift: ActiveWorkoutLiftView) => void;
  onChangeExercise: (lift: ActiveWorkoutLiftView) => void;
  onFeedbackNeeded: (lift: ActiveWorkoutLiftView) => void;
  onRemoveLastSet: (lift: ActiveWorkoutLiftView) => void;
  onSetFieldChange: (setId: number, field: keyof SetDraftValue, value: string) => void;
  onToggleMenu: (lift: ActiveWorkoutLiftView) => void;
  showFeedbackNeeded: boolean;
}) {
  const isSkipped = lift.status === "skipped";
  const canEditLift = !isReadOnly && !isSkipped && !lift.locked && !isLiftMutationSaving;
  const canAddSet = canEditLift && lift.sets.length < maxWorkingSets;
  const canRemoveSet = canEditLift && lift.sets.length > 1;
  const menuId = `lift-actions-menu-${lift.id}`;
  const className = [
    "lift-card",
    lift.status === "complete" ? "lift-card--complete" : "",
    isSkipped ? "lift-card--skipped" : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <article className={className} data-agent-id={`lift-card-${lift.id}`}>
      <div className="lift-card__header">
        <h2>{lift.exerciseName}</h2>
        <span className="lift-card__set-count">{isSkipped ? "Skipped" : `${lift.sets.length} sets`}</span>
        <div className="lift-card__menu" data-lift-menu-root={lift.id}>
          <button
            aria-controls={isMenuOpen ? menuId : undefined}
            aria-expanded={isMenuOpen}
            aria-haspopup="menu"
            aria-label={`Open actions for ${lift.exerciseName}`}
            className={isMenuOpen ? "lift-card__menu-toggle lift-card__menu-toggle--active" : "lift-card__menu-toggle"}
            data-agent-id={`lift-menu-toggle-${lift.id}`}
            disabled={!canEditLift}
            onClick={() => onToggleMenu(lift)}
            type="button"
          >
            <MoreVertical aria-hidden size={22} strokeWidth={2.5} />
          </button>

          {isMenuOpen ? (
            <div
              aria-label={`${lift.exerciseName} actions`}
              className="lift-card__menu-popover"
              data-agent-id={menuId}
              id={menuId}
              role="menu"
            >
              <button
                data-agent-id={`lift-change-exercise-${lift.id}`}
                onClick={() => onChangeExercise(lift)}
                role="menuitem"
                type="button"
              >
                <RefreshCw aria-hidden size={20} strokeWidth={2.4} />
                <span>
                  <strong>Change exercise</strong>
                  <small>Resets progression and sets</small>
                </span>
              </button>
              <button
                data-agent-id={`lift-add-set-${lift.id}`}
                disabled={!canAddSet}
                onClick={() => onAddSet(lift)}
                role="menuitem"
                type="button"
              >
                <Plus aria-hidden size={22} strokeWidth={2.5} />
                <span>
                  <strong>Add set</strong>
                  <small>{canAddSet ? "Adds one blank set" : `${maxWorkingSets} set limit`}</small>
                </span>
              </button>
              <button
                data-agent-id={`lift-remove-last-set-${lift.id}`}
                disabled={!canRemoveSet}
                onClick={() => onRemoveLastSet(lift)}
                role="menuitem"
                type="button"
              >
                <Minus aria-hidden size={22} strokeWidth={2.5} />
                <span>
                  <strong>Remove last set</strong>
                  <small>{canRemoveSet ? "Deletes the final row" : "Keep at least one set"}</small>
                </span>
              </button>
            </div>
          ) : null}
        </div>
      </div>

      {showFeedbackNeeded ? (
        <button
          className="feedback-needed-button"
          data-agent-id={`feedback-needed-lift-${lift.id}`}
          onClick={() => onFeedbackNeeded(lift)}
          type="button"
        >
          <AlertTriangle aria-hidden size={18} strokeWidth={2.4} />
          Feedback Needed
        </button>
      ) : null}

      <div className="set-list">
        {lift.sets.map((set) => (
          <SetRow
            draftValue={draftValues[set.id] ?? valueFromSet(set)}
            isReadOnly={isReadOnly || isSkipped || lift.locked || set.locked || set.status === "skipped"}
            key={set.id}
            onSetFieldChange={onSetFieldChange}
            repsOnly={lift.repsOnly}
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
  repsOnly,
  set,
}: {
  draftValue: SetDraftValue;
  isReadOnly: boolean;
  onSetFieldChange: (setId: number, field: keyof SetDraftValue, value: string) => void;
  repsOnly: boolean;
  set: ActiveWorkoutSetView;
}) {
  const isComplete = set.status === "complete";
  const isSkipped = set.status === "skipped";

  return (
    <div
      className={[
        "set-row",
        isComplete ? "set-row--complete" : "",
        isSkipped ? "set-row--skipped" : "",
      ]
        .filter(Boolean)
        .join(" ")}
      data-agent-id={`set-row-${set.id}`}
    >
      <div className="set-row__set">
        <strong>Set {set.order}</strong>
        {isComplete ? (
          <span className="set-row__logged" data-agent-id={`set-logged-${set.id}`}>
            <Check aria-hidden size={16} strokeWidth={2.5} />
            Logged
          </span>
        ) : isSkipped ? (
          <span className="set-row__skipped" data-agent-id={`set-skipped-${set.id}`}>
            Skipped
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
          disabled={isReadOnly || repsOnly}
          inputMode="numeric"
          onChange={(event) => onSetFieldChange(set.id, "weight", event.currentTarget.value)}
          pattern="[0-9]*"
          placeholder={set.plannedWeight?.toString() ?? ""}
          type="text"
          value={repsOnly ? bodyWeightDisplay : draftValue.weight}
        />
      </label>
    </div>
  );
}

function buildDraftValues(view: ActiveWorkoutView): SetDraftValues {
  return Object.fromEntries(
    view.lifts.flatMap((lift) =>
      lift.sets.map((set) => [
        set.id,
        valueFromSet(set, { prefillPlannedWeight: canUsePlannedWeightAsDraft(view, lift, set) }),
      ]),
    ),
  );
}

function findLiftAndSet(
  view: ActiveWorkoutView,
  setId: number,
): { lift: ActiveWorkoutLiftView; set: ActiveWorkoutSetView } | null {
  for (const lift of view.lifts) {
    const set = lift.sets.find((item) => item.id === setId);

    if (set) {
      return { lift, set };
    }
  }

  return null;
}

function isSetEditable(
  view: ActiveWorkoutView,
  lift: ActiveWorkoutLiftView,
  set: ActiveWorkoutSetView,
): boolean {
  return !view.isReadOnly && !lift.locked && lift.status !== "skipped" && !set.locked && set.status !== "skipped";
}

function valueFromSet(
  set: ActiveWorkoutSetView,
  options: { prefillPlannedWeight?: boolean } = {},
): SetDraftValue {
  const weight = set.actualWeight ?? (options.prefillPlannedWeight ? set.plannedWeight : null);

  return {
    reps: set.actualReps?.toString() ?? "",
    weight: weight?.toString() ?? "",
  };
}

function canUsePlannedWeightAsDraft(
  view: ActiveWorkoutView,
  lift: ActiveWorkoutLiftView,
  set: ActiveWorkoutSetView,
): boolean {
  return !view.isReadOnly && !lift.repsOnly && !lift.locked && !set.locked && set.status !== "skipped";
}

function isAllowedIntegerInput(value: string): boolean {
  return value === "" || /^[1-9]\d*$/.test(value);
}

function toNullableInteger(value: string): number | null {
  return value === "" ? null : Number(value);
}

function isRepsOnlySet(view: ActiveWorkoutView, setId: number): boolean {
  return view.lifts.some((lift) => lift.repsOnly && lift.sets.some((set) => set.id === setId));
}
