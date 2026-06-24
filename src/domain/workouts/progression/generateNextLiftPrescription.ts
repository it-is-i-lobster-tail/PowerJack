import {
  primaryMuscleSetCredit,
  secondaryMuscleSetCredit,
  weeklyMuscleSetProgressionCap,
} from "../../analytics/TrainingAnalytics";
import type { EntityId } from "../../ids";
import type { PowerJackStatus } from "../../status";

export type ProgressionGate =
  | "gate_1_high_pain"
  | "gate_2_under_minimum"
  | "gate_3_moderate_pain"
  | "gate_4_max_effort"
  | "gate_5_focus_volume"
  | "gate_6_non_focus_volume"
  | "gate_7_load"
  | "gate_7_reps"
  | "skipped_carry_forward";

export interface ProgressionExercise {
  minRepsHypertrophy: number;
  maxRepsHypertrophy: number;
  primaryMuscleId: EntityId;
  secondaryMuscleIds: EntityId[];
  repsOnly: boolean;
}

export interface ProgressionLiftSet {
  order: number;
  plannedReps: number | null;
  plannedWeight: number | null;
  actualReps: number | null;
  actualWeight: number | null;
  status: PowerJackStatus;
}

export interface ProgressionLiftHistory {
  id: EntityId;
  programWeek: number;
  status: PowerJackStatus;
  levelOfPain: number | null;
  levelOfEffort: number | null;
  manualCheckinSourceLiftId: EntityId | null;
  sets: ProgressionLiftSet[];
}

export interface NextLiftSetPrescription {
  order: number;
  plannedReps: number | null;
  plannedWeight: number | null;
}

export interface NextLiftPrescription {
  gate: ProgressionGate;
  manualCheckinSourceLiftId: EntityId | null;
  sets: NextLiftSetPrescription[];
}

export interface GenerateNextLiftPrescriptionInput {
  current: ProgressionLiftHistory;
  previous: ProgressionLiftHistory | null;
  twoWeeksAgo: ProgressionLiftHistory | null;
  exercise: ProgressionExercise;
  focusMuscleIds: EntityId[];
  programLengthWeeks: number;
  previousWeekMuscleSetCredits: ReadonlyMap<EntityId, number>;
}

const loadIncrementLb = 5;
const maxRelativeLoadJump = 0.1;
export const maxWorkingSets = 5;

export function generateNextLiftPrescription(
  input: GenerateNextLiftPrescriptionInput,
): NextLiftPrescription {
  const { current, exercise } = input;

  if (current.status === "skipped") {
    return carryForwardSkippedLift(current);
  }

  const currentSets = completedWorkingSets(current, exercise);
  const levelOfPain = requireFeedbackValue(current.levelOfPain, "pain");
  const levelOfEffort = requireFeedbackValue(current.levelOfEffort, "effort");

  if (levelOfPain >= 4) {
    return {
      gate: "gate_1_high_pain",
      manualCheckinSourceLiftId: current.id,
      sets: renumber(copyActualSets(currentSets)),
    };
  }

  const underMinimumSets = currentSets.filter((set) => set.actualReps < exercise.minRepsHypertrophy);

  if (underMinimumSets.length >= 1) {
    const firstUnderMinimumOrder = underMinimumSets[0]?.order;
    const retainedSets = currentSets.filter(
      (set) => set.actualReps >= exercise.minRepsHypertrophy || set.order === firstUnderMinimumOrder,
    );

    return {
      gate: "gate_2_under_minimum",
      manualCheckinSourceLiftId: null,
      sets: renumber(
        retainedSets.map((set) => ({
          order: set.order,
          plannedReps: Math.max(set.actualReps, exercise.minRepsHypertrophy),
          plannedWeight: set.actualWeight,
        })),
      ),
    };
  }

  if (levelOfPain === 3) {
    return {
      gate: "gate_3_moderate_pain",
      manualCheckinSourceLiftId: null,
      sets: renumber(copyActualSets(currentSets)),
    };
  }

  if (levelOfEffort === 5) {
    return {
      gate: "gate_4_max_effort",
      manualCheckinSourceLiftId: null,
      sets: renumber(copyActualSets(currentSets)),
    };
  }

  const isFocusMuscle = input.focusMuscleIds.includes(exercise.primaryMuscleId);

  if (
    isFocusMuscle &&
    isEligibleForVolume(current, exercise, input.programLengthWeeks) &&
    isEligibleForVolume(input.previous, exercise, input.programLengthWeeks) &&
    currentSets.length < maxWorkingSets &&
    canAddVolumeWithinWeeklyMuscleSetCap(exercise, input.previousWeekMuscleSetCredits)
  ) {
    return addVolumeSet("gate_5_focus_volume", currentSets);
  }

  if (
    !isFocusMuscle &&
    isEligibleForVolume(current, exercise, input.programLengthWeeks) &&
    isEligibleForVolume(input.previous, exercise, input.programLengthWeeks) &&
    isEligibleForVolume(input.twoWeeksAgo, exercise, input.programLengthWeeks) &&
    currentSets.length < maxWorkingSets &&
    canAddVolumeWithinWeeklyMuscleSetCap(exercise, input.previousWeekMuscleSetCredits)
  ) {
    return addVolumeSet("gate_6_non_focus_volume", currentSets);
  }

  const loadReadyRepThreshold = Math.ceil(0.85 * exercise.maxRepsHypertrophy);
  const canIncreaseLoad =
    !exercise.repsOnly &&
    currentSets.every(
      (set) =>
        set.actualReps >= loadReadyRepThreshold &&
        set.actualWeight !== null &&
        loadIncrementLb / set.actualWeight <= maxRelativeLoadJump,
    );

  if (canIncreaseLoad) {
    return {
      gate: "gate_7_load",
      manualCheckinSourceLiftId: null,
      sets: renumber(
        currentSets.map((set) => ({
          order: set.order,
          plannedReps: set.actualReps,
          plannedWeight: requireActualWeight(set) + loadIncrementLb,
        })),
      ),
    };
  }

  return {
    gate: "gate_7_reps",
    manualCheckinSourceLiftId: null,
    sets: renumber(
      currentSets.map((set) => ({
        order: set.order,
        plannedReps: Math.min(set.actualReps + 1, exercise.maxRepsHypertrophy),
        plannedWeight: set.actualWeight,
      })),
    ),
  };
}

function carryForwardSkippedLift(current: ProgressionLiftHistory): NextLiftPrescription {
  if (!current.manualCheckinSourceLiftId) {
    throw new Error("Skipped lift cannot be carried forward without a manual check-in source.");
  }

  const setPlans = current.sets
    .slice()
    .sort((left, right) => left.order - right.order)
    .map((set) => {
      if (set.plannedReps === null) {
        throw new Error("Skipped lift is missing its held prescription.");
      }

      return {
        order: set.order,
        plannedReps: set.plannedReps,
        plannedWeight: set.plannedWeight,
      };
    });

  return {
    gate: "skipped_carry_forward",
    manualCheckinSourceLiftId: current.manualCheckinSourceLiftId,
    sets: renumber(setPlans),
  };
}

function addVolumeSet(
  gate: "gate_5_focus_volume" | "gate_6_non_focus_volume",
  currentSets: CompletedProgressionSet[],
): NextLiftPrescription {
  const copiedSets = copyActualSets(currentSets);
  const lastSet = currentSets[currentSets.length - 1];

  if (!lastSet) {
    throw new Error("Cannot add volume to a lift with no completed sets.");
  }

  return {
    gate,
    manualCheckinSourceLiftId: null,
    sets: renumber([
      ...copiedSets,
      {
        order: lastSet.order + 1,
        plannedReps: null,
        plannedWeight: lastSet.actualWeight,
      },
    ]),
  };
}

function canAddVolumeWithinWeeklyMuscleSetCap(
  exercise: ProgressionExercise,
  previousWeekMuscleSetCredits: ReadonlyMap<EntityId, number>,
): boolean {
  return projectedAddedSetMuscleCredits(exercise).every(
    ({ muscleId, setCredit }) =>
      (previousWeekMuscleSetCredits.get(muscleId) ?? 0) + setCredit <= weeklyMuscleSetProgressionCap,
  );
}

function projectedAddedSetMuscleCredits(
  exercise: ProgressionExercise,
): Array<{ muscleId: EntityId; setCredit: number }> {
  return [
    { muscleId: exercise.primaryMuscleId, setCredit: primaryMuscleSetCredit },
    ...exercise.secondaryMuscleIds
      .filter((muscleId) => muscleId !== exercise.primaryMuscleId)
      .map((muscleId) => ({ muscleId, setCredit: secondaryMuscleSetCredit })),
  ];
}

function isEligibleForVolume(
  lift: ProgressionLiftHistory | null,
  exercise: ProgressionExercise,
  programLengthWeeks: number,
): boolean {
  if (!lift || lift.status === "skipped" || lift.levelOfPain === null || lift.levelOfEffort === null) {
    return false;
  }

  if (lift.levelOfPain > 2 || lift.levelOfEffort > targetEffortCeiling(lift.programWeek, programLengthWeeks)) {
    return false;
  }

  return completedWorkingSets(lift, exercise).every((set) => set.actualReps >= exercise.minRepsHypertrophy);
}

type CompletedProgressionSet = ProgressionLiftSet & { actualReps: number; actualWeight: number | null };

function targetEffortCeiling(programWeek: number, programLengthWeeks: number): number {
  const progress = programWeek / programLengthWeeks;

  if (progress <= 0.2) {
    return 2;
  }

  if (progress <= 0.5) {
    return 3;
  }

  return 4;
}

function completedWorkingSets(
  lift: ProgressionLiftHistory,
  exercise: ProgressionExercise,
): CompletedProgressionSet[] {
  const sets = lift.sets
    .filter((set) => set.status !== "skipped")
    .slice()
    .sort((left, right) => left.order - right.order);

  if (sets.length === 0) {
    throw new Error("Cannot progress a lift with no working sets.");
  }

  return sets.map((set) => {
    if (set.actualReps === null || (!exercise.repsOnly && set.actualWeight === null)) {
      throw new Error("Cannot progress a lift before every working set is logged.");
    }

    return { ...set, actualReps: set.actualReps, actualWeight: set.actualWeight };
  });
}

function copyActualSets(
  sets: CompletedProgressionSet[],
): NextLiftSetPrescription[] {
  return sets.map((set) => ({
    order: set.order,
    plannedReps: set.actualReps,
    plannedWeight: set.actualWeight,
  }));
}

function requireActualWeight(set: CompletedProgressionSet): number {
  if (set.actualWeight === null) {
    throw new Error("Cannot add load to a lift without logged weight.");
  }

  return set.actualWeight;
}

function renumber(sets: NextLiftSetPrescription[]): NextLiftSetPrescription[] {
  return sets
    .slice()
    .sort((left, right) => left.order - right.order)
    .map((set, index) => ({ ...set, order: index + 1 }));
}

function requireFeedbackValue(value: number | null, label: string): number {
  if (value === null) {
    throw new Error(`Cannot progress a lift without ${label} feedback.`);
  }

  return value;
}
