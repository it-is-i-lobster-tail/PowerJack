import { create } from "zustand";
import type { TemplateAggregate, TemplateDraft } from "../../../domain/templates/Template";

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
  setName: (value: string) => void;
  toggleFocusMuscle: (id: number) => void;
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

export const useTemplateDraftStore = create<TemplateDraftState>((set, get) => ({
  editingTemplateId: null,
  returnPath: DEFAULT_TEMPLATE_FLOW_RETURN_PATH,
  name: "",
  focusMuscleIds: [],
  workoutsPerWeek: null,
  activeDay: 1,
  exerciseIdsByDay: {},
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
  setWorkoutsPerWeek: (workoutsPerWeek) =>
    set((state) => {
      const nextExerciseIdsByDay: Record<number, number[]> = {};

      for (let day = 1; day <= workoutsPerWeek; day += 1) {
        nextExerciseIdsByDay[day] = state.exerciseIdsByDay[day] ?? [];
      }

      return {
        workoutsPerWeek,
        activeDay: Math.min(state.activeDay, workoutsPerWeek),
        exerciseIdsByDay: nextExerciseIdsByDay,
      };
    }),
  setActiveDay: (activeDay) => set({ activeDay }),
  addExerciseToDay: (day, exerciseId) =>
    set((state) => ({
      exerciseIdsByDay: {
        ...state.exerciseIdsByDay,
        [day]: [...(state.exerciseIdsByDay[day] ?? []), exerciseId],
      },
    })),
  reorderExerciseInDay: (day, fromIndex, toIndex) =>
    set((state) => {
      const dayExerciseIds = state.exerciseIdsByDay[day] ?? [];

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

      return {
        exerciseIdsByDay: {
          ...state.exerciseIdsByDay,
          [day]: nextDayExerciseIds,
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
    })),
  loadFromAggregate: (template, returnPath = DEFAULT_TEMPLATE_FLOW_RETURN_PATH) => {
    const exerciseIdsByDay = template.days.reduce<Record<number, number[]>>((days, day) => {
      days[day.order] = [...day.exerciseIds];
      return days;
    }, {});

    set({
      editingTemplateId: template.id,
      returnPath,
      name: template.name,
      focusMuscleIds: [...template.focusMuscleIds],
      workoutsPerWeek: template.workoutsPerWeek,
      activeDay: template.days[0]?.order ?? 1,
      exerciseIdsByDay,
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
    }),
}));
