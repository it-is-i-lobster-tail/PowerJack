import { afterEach, describe, expect, it } from "vitest";
import { TEMPLATE_DAY_EXERCISE_MAX } from "../../src/domain/templates/rules/templateDraftLimits";
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

  it("keeps stable row ids with exercises through reorder replace and remove", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(1);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(1, 20);
    store.addExerciseToDay(1, 10);

    const [firstRowId, secondRowId, thirdRowId] = useTemplateDraftStore.getState().exerciseRowIdsByDay[1] ?? [];

    useTemplateDraftStore.getState().reorderExerciseInDay(1, 2, 0);

    expect(useTemplateDraftStore.getState().exerciseIdsByDay[1]).toEqual([10, 10, 20]);
    expect(useTemplateDraftStore.getState().exerciseRowIdsByDay[1]).toEqual([thirdRowId, firstRowId, secondRowId]);

    useTemplateDraftStore.getState().replaceExerciseInDay(1, 1, 99);

    expect(useTemplateDraftStore.getState().exerciseIdsByDay[1]).toEqual([10, 99, 20]);
    expect(useTemplateDraftStore.getState().exerciseRowIdsByDay[1]).toEqual([thirdRowId, firstRowId, secondRowId]);

    useTemplateDraftStore.getState().removeExerciseFromDay(1, 1);

    expect(useTemplateDraftStore.getState().exerciseIdsByDay[1]).toEqual([10, 20]);
    expect(useTemplateDraftStore.getState().exerciseRowIdsByDay[1]).toEqual([thirdRowId, secondRowId]);
  });

  it("limits added exercises to 20 per day without affecting other days", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(2);

    for (let index = 1; index <= TEMPLATE_DAY_EXERCISE_MAX + 1; index += 1) {
      useTemplateDraftStore.getState().addExerciseToDay(1, index);
    }

    useTemplateDraftStore.getState().addExerciseToDay(2, 99);

    const state = useTemplateDraftStore.getState();

    expect(state.exerciseIdsByDay[1]).toHaveLength(TEMPLATE_DAY_EXERCISE_MAX);
    expect(state.exerciseIdsByDay[1]).not.toContain(TEMPLATE_DAY_EXERCISE_MAX + 1);
    expect(state.exerciseRowIdsByDay[1]).toHaveLength(TEMPLATE_DAY_EXERCISE_MAX);
    expect(state.exerciseIdsByDay[2]).toEqual([99]);
  });

  it("copies exercises to another day by replacing the target with fresh row ids", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(3);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(1, 20);
    store.addExerciseToDay(2, 30);
    store.setActiveDay(1);

    const sourceRowIds = useTemplateDraftStore.getState().exerciseRowIdsByDay[1] ?? [];
    const previousTargetRowIds = useTemplateDraftStore.getState().exerciseRowIdsByDay[2] ?? [];

    useTemplateDraftStore.getState().copyExercisesToDay(1, 2);

    const state = useTemplateDraftStore.getState();

    expect(state.activeDay).toBe(1);
    expect(state.exerciseIdsByDay[1]).toEqual([10, 20]);
    expect(state.exerciseIdsByDay[2]).toEqual([10, 20]);
    expect(state.exerciseRowIdsByDay[2]).toHaveLength(2);
    expect(state.exerciseRowIdsByDay[2]).not.toEqual(sourceRowIds);
    expect(state.exerciseRowIdsByDay[2]).not.toEqual(previousTargetRowIds);
  });

  it("ignores same-day and invalid day copy requests", () => {
    const store = useTemplateDraftStore.getState();

    store.setWorkoutsPerWeek(2);
    store.addExerciseToDay(1, 10);
    store.addExerciseToDay(2, 20);

    useTemplateDraftStore.getState().copyExercisesToDay(1, 1);
    useTemplateDraftStore.getState().copyExercisesToDay(1, 3);
    useTemplateDraftStore.getState().copyExercisesToDay(0, 2);

    expect(useTemplateDraftStore.getState().exerciseIdsByDay).toEqual({
      1: [10],
      2: [20],
    });
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
    const retainedDayThreeRowId = useTemplateDraftStore.getState().exerciseRowIdsByDay[3]?.[0];

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
    expect(useTemplateDraftStore.getState().exerciseRowIdsByDay[2]).toEqual([retainedDayThreeRowId]);
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
