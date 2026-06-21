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

  it("resets to the new-program return path by default", () => {
    useTemplateDraftStore.getState().reset("/templates");
    useTemplateDraftStore.getState().reset();

    expect(useTemplateDraftStore.getState().returnPath).toBe("/start/select-template");
  });

  it("tracks templates-list return path for new and edited templates", () => {
    useTemplateDraftStore.getState().reset("/templates");

    expect(useTemplateDraftStore.getState().returnPath).toBe("/templates");

    useTemplateDraftStore.getState().loadFromAggregate(
      {
        id: 42,
        name: "Loaded Template",
        workoutsPerWeek: 2,
        focusMuscleIds: [1, 2],
        days: [
          { id: 101, order: 1, exerciseIds: [10, 20] },
          { id: 102, order: 2, exerciseIds: [30] },
        ],
      },
      "/templates",
    );

    expect(useTemplateDraftStore.getState()).toMatchObject({
      editingTemplateId: 42,
      returnPath: "/templates",
    });
  });
});
