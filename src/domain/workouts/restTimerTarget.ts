import type { EntityId } from "../ids";
import type { ActiveWorkoutLiftView, ActiveWorkoutSetView, ActiveWorkoutView } from "./Workout";

const secondsPerTimeBasedRep = 15;
const emptySetValueLabel = "--";
const bodyWeightDisplay = "BW";

export interface RestTimerTarget {
  workoutId: EntityId;
  liftId: EntityId;
  setId: EntityId;
  setOrder: number;
  liftOrder: number;
  label: string;
  shortLabel: string;
}

export function findNextIncompleteRestTimerTarget(view: ActiveWorkoutView): RestTimerTarget | null {
  for (const lift of view.lifts) {
    if (lift.status === "skipped") {
      continue;
    }

    for (const set of lift.sets) {
      if (isIncompleteRestTimerSet(set)) {
        return buildRestTimerTarget(view, lift, set);
      }
    }
  }

  return null;
}

export function findRestTimerTargetBySetId(
  view: ActiveWorkoutView,
  setId: EntityId | null,
): RestTimerTarget | null {
  if (setId === null) {
    return null;
  }

  for (const lift of view.lifts) {
    const set = lift.sets.find((item) => item.id === setId);

    if (set && isIncompleteRestTimerSet(set)) {
      return buildRestTimerTarget(view, lift, set);
    }
  }

  return null;
}

export function didAnySetBecomeComplete(
  previousView: ActiveWorkoutView | null,
  nextView: ActiveWorkoutView,
): boolean {
  if (!previousView) {
    return false;
  }

  const previousSetsById = buildSetsById(previousView);

  return nextView.lifts.some((lift) =>
    lift.sets.some((set) => previousSetsById.get(set.id)?.status !== "complete" && set.status === "complete"),
  );
}

export function didAnySetBecomeIncomplete(
  previousView: ActiveWorkoutView | null,
  nextView: ActiveWorkoutView,
): boolean {
  if (!previousView) {
    return false;
  }

  const previousSetsById = buildSetsById(previousView);

  return nextView.lifts.some((lift) =>
    lift.sets.some((set) => previousSetsById.get(set.id)?.status === "complete" && set.status !== "complete"),
  );
}

export function isIncompleteRestTimerSet(set: ActiveWorkoutSetView): boolean {
  return set.status !== "complete" && set.status !== "skipped";
}

function buildRestTimerTarget(
  view: ActiveWorkoutView,
  lift: ActiveWorkoutLiftView,
  set: ActiveWorkoutSetView,
): RestTimerTarget {
  const prescription = formatSetPrescription(lift, set);
  const shortLabel = `Set ${set.order}`;

  return {
    workoutId: view.workout.id,
    liftId: lift.id,
    setId: set.id,
    setOrder: set.order,
    liftOrder: lift.order,
    label: `${shortLabel} \u2022 ${prescription}`,
    shortLabel,
  };
}

function formatSetPrescription(lift: ActiveWorkoutLiftView, set: ActiveWorkoutSetView): string {
  const fallbackSet = findNearestPriorCompletedSet(lift, set.order);
  const reps = set.actualReps ?? set.plannedReps ?? fallbackSet?.actualReps ?? fallbackSet?.plannedReps ?? null;
  const weight = lift.repsOnly
    ? bodyWeightDisplay
    : (set.actualWeight ?? set.plannedWeight ?? fallbackSet?.actualWeight ?? fallbackSet?.plannedWeight ?? null);
  const repsLabel = reps === null ? emptySetValueLabel : formatReps(reps, lift.timeBased);
  const weightLabel = weight === null ? emptySetValueLabel : weight.toString();

  return `${repsLabel} \u00d7 ${weightLabel}`;
}

function formatReps(reps: number, timeBased: boolean): string {
  return (timeBased ? reps * secondsPerTimeBasedRep : reps).toString();
}

function findNearestPriorCompletedSet(
  lift: ActiveWorkoutLiftView,
  setOrder: number,
): ActiveWorkoutSetView | null {
  return (
    [...lift.sets]
      .filter((set) => set.order < setOrder && set.status === "complete")
      .sort((left, right) => right.order - left.order)[0] ?? null
  );
}

function buildSetsById(view: ActiveWorkoutView): Map<EntityId, ActiveWorkoutSetView> {
  return new Map(view.lifts.flatMap((lift) => lift.sets.map((set) => [set.id, set] as const)));
}
