import { create } from "zustand";
import type { TemplateAggregate, TemplateDraft } from "../../../domain/templates/Template";

export interface WorkoutsPerWeekChangePlan {
  daysToRemove: number[];
  requiresConfirmation: boolean;
  workoutsPerWeek: number;
}

export const DEFAULT_TEMPLATE_FLOW_RETURN_PATH = "/start/select-template";
export type TemplateFlowReturnPath = typeof DEFAULT_TEMPLATE_FLOW_RETURN_PATH | "/templates";

interface TemplateDraftState {
  editingTemplateId: number | null;
  returnPath: TemplateFlowReturnPath;
  name: string;
  focusMuscleIds: number[];
  workoutsPerWeek: number | null;
  activeDay: number;
  exerciseIdsByDay: Record<number, number[]>;
  exerciseRowIdsByDay: Record<number, string[]>;
  nextExerciseRowId: number;
  setName: (value: string) => void;
  toggleFocusMuscle: (id: number) => void;
  previewWorkoutsPerWeekChange: (value: number) => WorkoutsPerWeekChangePlan;
  setWorkoutsPerWeek: (value: number) => void;
  setActiveDay: (day: number) => void;
  addExerciseToDay: (day: number, exerciseId: number) => void;
  reorderExerciseInDay: (day: number, fromIndex: number, toIndex: number) => void;
  replaceExerciseInDay: (day: number, index: number, exerciseId: number) => void;
  removeExerciseFromDay: (day: number, index: number) => void;
  loadFromAggregate: (template: TemplateAggregate, returnPath?: TemplateFlowReturnPath) => void;
  toDraft: () => TemplateDraft;
  reset: (returnPath?: TemplateFlowReturnPath) => void;
}

function buildDays(workoutsPerWeek: number | null, exerciseIdsByDay: Record<number, number[]>): TemplateDraft["days"] {
  if (!workoutsPerWeek) {
    return [];
  }

  return Array.from({ length: workoutsPerWeek }, (_, index) => {
    const order = index + 1;
    return {
      order,
      exerciseIds: exerciseIdsByDay[order] ?? [],
    };
  });
}

function buildExerciseRowId(value: number): string {
  return `template-exercise-row-${value}`;
}

function ensureExerciseRowIds(
  exerciseIds: number[],
  existingRowIds: string[] | undefined,
  nextExerciseRowId: number,
): { rowIds: string[]; nextExerciseRowId: number } {
  const rowIds = existingRowIds?.slice(0, exerciseIds.length) ?? [];
  let nextId = nextExerciseRowId;

  while (rowIds.length < exerciseIds.length) {
    rowIds.push(buildExerciseRowId(nextId));
    nextId += 1;
  }

  return { rowIds, nextExerciseRowId: nextId };
}

function buildExerciseRowIdsByDay(
  exerciseIdsByDay: Record<number, number[]>,
  startingRowId = 1,
): { exerciseRowIdsByDay: Record<number, string[]>; nextExerciseRowId: number } {
  let nextExerciseRowId = startingRowId;
  const exerciseRowIdsByDay: Record<number, string[]> = {};

  for (const [day, exerciseIds] of Object.entries(exerciseIdsByDay)) {
    const result = ensureExerciseRowIds(exerciseIds, undefined, nextExerciseRowId);
    exerciseRowIdsByDay[Number(day)] = result.rowIds;
    nextExerciseRowId = result.nextExerciseRowId;
  }

  return { exerciseRowIdsByDay, nextExerciseRowId };
}

function getExistingDayOrders(workoutsPerWeek: number | null): number[] {
  if (!workoutsPerWeek) {
    return [];
  }

  return Array.from({ length: workoutsPerWeek }, (_, index) => index + 1);
}

function planWorkoutsPerWeekChange(
  workoutsPerWeek: number | null,
  exerciseIdsByDay: Record<number, number[]>,
  nextWorkoutsPerWeek: number,
): WorkoutsPerWeekChangePlan {
  if (!workoutsPerWeek || nextWorkoutsPerWeek >= workoutsPerWeek) {
    return {
      daysToRemove: [],
      requiresConfirmation: false,
      workoutsPerWeek: nextWorkoutsPerWeek,
    };
  }

  const removeCount = workoutsPerWeek - nextWorkoutsPerWeek;
  const existingDayOrders = getExistingDayOrders(workoutsPerWeek);
  const emptyDays = existingDayOrders
    .filter((day) => (exerciseIdsByDay[day] ?? []).length === 0)
    .sort((left, right) => right - left);
  const filledDays = existingDayOrders
    .filter((day) => (exerciseIdsByDay[day] ?? []).length > 0)
    .sort((left, right) => right - left);
  const emptyDaysToRemove = emptyDays.slice(0, removeCount);
  const filledDaysToRemove = filledDays.slice(0, Math.max(0, removeCount - emptyDaysToRemove.length));
  const daysToRemove = [...emptyDaysToRemove, ...filledDaysToRemove].sort((left, right) => left - right);

  return {
    daysToRemove,
    requiresConfirmation: filledDaysToRemove.length > 0,
    workoutsPerWeek: nextWorkoutsPerWeek,
  };
}

function buildExerciseRowsByDayAfterChange({
  currentWorkoutsPerWeek,
  exerciseIdsByDay,
  exerciseRowIdsByDay,
  nextExerciseRowId,
  plan,
}: {
  currentWorkoutsPerWeek: number | null;
  exerciseIdsByDay: Record<number, number[]>;
  exerciseRowIdsByDay: Record<number, string[]>;
  nextExerciseRowId: number;
  plan: WorkoutsPerWeekChangePlan;
}): {
  exerciseIdsByDay: Record<number, number[]>;
  exerciseRowIdsByDay: Record<number, string[]>;
  nextExerciseRowId: number;
} {
  let nextRowId = nextExerciseRowId;
  const nextExerciseIdsByDay: Record<number, number[]> = {};
  const nextExerciseRowIdsByDay: Record<number, string[]> = {};

  function copyDay(originalDay: number, nextDay: number): void {
    const exerciseIds = exerciseIdsByDay[originalDay] ?? [];
    const result = ensureExerciseRowIds(exerciseIds, exerciseRowIdsByDay[originalDay], nextRowId);
    nextExerciseIdsByDay[nextDay] = exerciseIds;
    nextExerciseRowIdsByDay[nextDay] = result.rowIds;
    nextRowId = result.nextExerciseRowId;
  }

  if (!currentWorkoutsPerWeek || plan.workoutsPerWeek >= currentWorkoutsPerWeek) {
    for (let day = 1; day <= plan.workoutsPerWeek; day += 1) {
      copyDay(day, day);
    }

    return {
      exerciseIdsByDay: nextExerciseIdsByDay,
      exerciseRowIdsByDay: nextExerciseRowIdsByDay,
      nextExerciseRowId: nextRowId,
    };
  }

  const removedDays = new Set(plan.daysToRemove);
  const retainedDays = getExistingDayOrders(currentWorkoutsPerWeek).filter((day) => !removedDays.has(day));

  retainedDays.slice(0, plan.workoutsPerWeek).forEach((originalDay, index) => {
    copyDay(originalDay, index + 1);
  });

  return {
    exerciseIdsByDay: nextExerciseIdsByDay,
    exerciseRowIdsByDay: nextExerciseRowIdsByDay,
    nextExerciseRowId: nextRowId,
  };
}

export const useTemplateDraftStore = create<TemplateDraftState>((set, get) => ({
  editingTemplateId: null,
  returnPath: DEFAULT_TEMPLATE_FLOW_RETURN_PATH,
  name: "",
  focusMuscleIds: [],
  workoutsPerWeek: null,
  activeDay: 1,
  exerciseIdsByDay: {},
  exerciseRowIdsByDay: {},
  nextExerciseRowId: 1,
  setName: (name) => set({ name }),
  toggleFocusMuscle: (id) =>
    set((state) => {
      if (state.focusMuscleIds.includes(id)) {
        return { focusMuscleIds: state.focusMuscleIds.filter((muscleId) => muscleId !== id) };
      }

      if (state.focusMuscleIds.length >= 4) {
        return state;
      }

      return { focusMuscleIds: [...state.focusMuscleIds, id] };
    }),
  previewWorkoutsPerWeekChange: (workoutsPerWeek) => {
    const state = get();
    return planWorkoutsPerWeekChange(state.workoutsPerWeek, state.exerciseIdsByDay, workoutsPerWeek);
  },
  setWorkoutsPerWeek: (workoutsPerWeek) =>
    set((state) => {
      const plan = planWorkoutsPerWeekChange(state.workoutsPerWeek, state.exerciseIdsByDay, workoutsPerWeek);
      const nextRows = buildExerciseRowsByDayAfterChange({
        currentWorkoutsPerWeek: state.workoutsPerWeek,
        exerciseIdsByDay: state.exerciseIdsByDay,
        exerciseRowIdsByDay: state.exerciseRowIdsByDay,
        nextExerciseRowId: state.nextExerciseRowId,
        plan,
      });

      return {
        workoutsPerWeek,
        activeDay: Math.min(state.activeDay, workoutsPerWeek),
        exerciseIdsByDay: nextRows.exerciseIdsByDay,
        exerciseRowIdsByDay: nextRows.exerciseRowIdsByDay,
        nextExerciseRowId: nextRows.nextExerciseRowId,
      };
    }),
  setActiveDay: (activeDay) => set({ activeDay }),
  addExerciseToDay: (day, exerciseId) =>
    set((state) => {
      const rowId = buildExerciseRowId(state.nextExerciseRowId);

      return {
        exerciseIdsByDay: {
          ...state.exerciseIdsByDay,
          [day]: [...(state.exerciseIdsByDay[day] ?? []), exerciseId],
        },
        exerciseRowIdsByDay: {
          ...state.exerciseRowIdsByDay,
          [day]: [...(state.exerciseRowIdsByDay[day] ?? []), rowId],
        },
        nextExerciseRowId: state.nextExerciseRowId + 1,
      };
    }),
  reorderExerciseInDay: (day, fromIndex, toIndex) =>
    set((state) => {
      const dayExerciseIds = state.exerciseIdsByDay[day] ?? [];
      const dayExerciseRowIds = state.exerciseRowIdsByDay[day] ?? [];

      if (
        fromIndex === toIndex ||
        fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= dayExerciseIds.length ||
        toIndex >= dayExerciseIds.length
      ) {
        return state;
      }

      const nextDayExerciseIds = [...dayExerciseIds];
      const [movedExerciseId] = nextDayExerciseIds.splice(fromIndex, 1);
      nextDayExerciseIds.splice(toIndex, 0, movedExerciseId);
      const nextDayExerciseRowIds = [...dayExerciseRowIds];
      const [movedExerciseRowId] = nextDayExerciseRowIds.splice(fromIndex, 1);

      if (movedExerciseRowId) {
        nextDayExerciseRowIds.splice(toIndex, 0, movedExerciseRowId);
      }

      return {
        exerciseIdsByDay: {
          ...state.exerciseIdsByDay,
          [day]: nextDayExerciseIds,
        },
        exerciseRowIdsByDay: {
          ...state.exerciseRowIdsByDay,
          [day]: nextDayExerciseRowIds,
        },
      };
    }),
  replaceExerciseInDay: (day, index, exerciseId) =>
    set((state) => {
      const dayExerciseIds = state.exerciseIdsByDay[day] ?? [];

      if (index < 0 || index >= dayExerciseIds.length) {
        return state;
      }

      const nextDayExerciseIds = [...dayExerciseIds];
      nextDayExerciseIds[index] = exerciseId;

      return {
        exerciseIdsByDay: {
          ...state.exerciseIdsByDay,
          [day]: nextDayExerciseIds,
        },
      };
    }),
  removeExerciseFromDay: (day, index) =>
    set((state) => ({
      exerciseIdsByDay: {
        ...state.exerciseIdsByDay,
        [day]: (state.exerciseIdsByDay[day] ?? []).filter((_, itemIndex) => itemIndex !== index),
      },
      exerciseRowIdsByDay: {
        ...state.exerciseRowIdsByDay,
        [day]: (state.exerciseRowIdsByDay[day] ?? []).filter((_, itemIndex) => itemIndex !== index),
      },
    })),
  loadFromAggregate: (template, returnPath = DEFAULT_TEMPLATE_FLOW_RETURN_PATH) => {
    const exerciseIdsByDay = template.days.reduce<Record<number, number[]>>((days, day) => {
      days[day.order] = [...day.exerciseIds];
      return days;
    }, {});
    const { exerciseRowIdsByDay, nextExerciseRowId } = buildExerciseRowIdsByDay(exerciseIdsByDay);

    set({
      editingTemplateId: template.id,
      returnPath,
      name: template.name,
      focusMuscleIds: [...template.focusMuscleIds],
      workoutsPerWeek: template.workoutsPerWeek,
      activeDay: template.days[0]?.order ?? 1,
      exerciseIdsByDay,
      exerciseRowIdsByDay,
      nextExerciseRowId,
    });
  },
  toDraft: () => {
    const state = get();
    return {
      name: state.name,
      focusMuscleIds: state.focusMuscleIds,
      workoutsPerWeek: state.workoutsPerWeek,
      days: buildDays(state.workoutsPerWeek, state.exerciseIdsByDay),
    };
  },
  reset: (returnPath = DEFAULT_TEMPLATE_FLOW_RETURN_PATH) =>
    set({
      editingTemplateId: null,
      returnPath,
      name: "",
      focusMuscleIds: [],
      workoutsPerWeek: null,
      activeDay: 1,
      exerciseIdsByDay: {},
      exerciseRowIdsByDay: {},
      nextExerciseRowId: 1,
    }),
}));
