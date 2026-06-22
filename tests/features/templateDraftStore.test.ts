import { afterEach, describe, expect, it } from "vitest";
import { useTemplateDraftStore } from "../../src/features/templates/state/templateDraftStore";

describe("templateDraftStore", () => {
  afterEach(() => {
    useTemplateDraftStore.getState().reset();
  });

  it("reorders exercises within a day", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(1);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(1, 20);
    store.addExerciseToDay(1, 30);
    useTemplateDraftStore.getState().reorderExerciseInDay(1, 2, 0);

    expect(useTemplateDraftStore.getState().exerciseIdsByDay[1]).toEqual([30, 10, 20]);
  });

  it("replaces only the targeted exercise index", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(1);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(1, 20);
    store.addExerciseToDay(1, 30);
    useTemplateDraftStore.getState().replaceExerciseInDay(1, 1, 99);

    expect(useTemplateDraftStore.getState().exerciseIdsByDay[1]).toEqual([10, 99, 30]);
  });

  it("removes the correct exercise after reordering", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(1);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(1, 20);
    store.addExerciseToDay(1, 30);
    useTemplateDraftStore.getState().reorderExerciseInDay(1, 2, 0);
    useTemplateDraftStore.getState().removeExerciseFromDay(1, 1);

    expect(useTemplateDraftStore.getState().exerciseIdsByDay[1]).toEqual([30, 20]);
  });

  it("reduces workouts per week by removing empty days before filled days", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(4);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(1, 20);
    store.addExerciseToDay(1, 30);
    store.addExerciseToDay(1, 40);

    expect(useTemplateDraftStore.getState().previewWorkoutsPerWeekChange(2)).toEqual({
      daysToRemove: [3, 4],
      requiresConfirmation: false,
      workoutsPerWeek: 2,
    });

    useTemplateDraftStore.getState().setWorkoutsPerWeek(2);

    expect(useTemplateDraftStore.getState()).toMatchObject({
      workoutsPerWeek: 2,
      activeDay: 1,
      exerciseIdsByDay: {
        1: [10, 20, 30, 40],
        2: [],
      },
    });
  });

  it("plans a confirmation when reducing workouts per week would remove a filled day", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(4);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(2, 20);
    store.addExerciseToDay(3, 30);

    expect(useTemplateDraftStore.getState().previewWorkoutsPerWeekChange(2)).toEqual({
      daysToRemove: [3, 4],
      requiresConfirmation: true,
      workoutsPerWeek: 2,
    });

    useTemplateDraftStore.getState().setActiveDay(3);
    useTemplateDraftStore.getState().setWorkoutsPerWeek(2);

    expect(useTemplateDraftStore.getState()).toMatchObject({
      workoutsPerWeek: 2,
      activeDay: 2,
      exerciseIdsByDay: {
        1: [10],
        2: [20],
      },
    });
  });

  it("compacts retained filled days when empty days are removed from the middle", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(4);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(3, 30);

    expect(useTemplateDraftStore.getState().previewWorkoutsPerWeekChange(2)).toEqual({
      daysToRemove: [2, 4],
      requiresConfirmation: false,
      workoutsPerWeek: 2,
    });

    useTemplateDraftStore.getState().setWorkoutsPerWeek(2);

    expect(useTemplateDraftStore.getState().exerciseIdsByDay).toEqual({
      1: [10],
      2: [30],
    });
  });

  it("loads an existing template aggregate for editing", () => {
    useTemplateDraftStore.getState().loadFromAggregate({
      id: 42,
      name: "Loaded Template",
      workoutsPerWeek: 2,
      focusMuscleIds: [1, 2],
      days: [
        { id: 101, order: 1, exerciseIds: [10, 20] },
        { id: 102, order: 2, exerciseIds: [30] },
      ],
    });

    expect(useTemplateDraftStore.getState()).toMatchObject({
      editingTemplateId: 42,
      name: "Loaded Template",
      workoutsPerWeek: 2,
      focusMuscleIds: [1, 2],
      activeDay: 1,
      exerciseIdsByDay: {
        1: [10, 20],
        2: [30],
      },
    });
  });
});
