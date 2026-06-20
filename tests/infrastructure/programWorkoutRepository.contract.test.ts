import { describe, expect, it } from "vitest";
import { loadProgramOverview } from "../../src/application/programs/loadProgramOverview";
import { startProgramFromTemplate } from "../../src/application/programs/startProgramFromTemplate";
import { saveTemplate } from "../../src/application/templates/saveTemplate";
import { finishWorkout } from "../../src/application/workouts/finishWorkout";
import { submitLiftFeedback } from "../../src/application/workouts/submitLiftFeedback";
import { updateWorkoutSet } from "../../src/application/workouts/updateWorkoutSet";
import type { AppServices } from "../../src/app/AppServices";
import type { ActiveWorkoutView } from "../../src/domain/workouts/Workout";
import { createInMemoryAppServices } from "../../src/infrastructure/database/repositories/InMemoryRepositories";

describe("Program and Workout repository contracts", () => {
  it("starts a program from a template and creates week 1 as active/planned workouts", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1], [2]]);

    await startProgramFromTemplate(
      { templateId: template.id, programLengthWeeks: 4 },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    const view = await loadRequiredActiveWorkout(services);
    const appState = await services.appState.load();

    expect(view.program).toMatchObject({
      name: "Back In Action x1",
      programLengthWeeks: 4,
      status: "active",
      locked: false,
    });
    expect(view.workout).toMatchObject({
      workoutDay: 1,
      programWeek: 1,
      status: "active",
      locked: false,
    });
    expect(view.weekWorkouts).toEqual([
      expect.objectContaining({ workoutDay: 1, status: "active", locked: false }),
      expect.objectContaining({ workoutDay: 2, status: "planned", locked: true }),
    ]);
    expect(view.lifts).toHaveLength(1);
    expect(view.lifts[0]?.sets).toHaveLength(2);
    expect(view.lifts[0]?.sets).toEqual([
      expect.objectContaining({ order: 1, status: "active", locked: false }),
      expect.objectContaining({ order: 2, status: "active", locked: false }),
    ]);
    expect(appState).toMatchObject({
      activeProgramId: view.program.id,
      activeWorkoutId: view.workout.id,
      activeLiftId: view.lifts[0]?.id,
    });
  });

  it("loads a reusable program overview with future weeks synthesized from the template", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1], [2]]);

    await startProgramFromTemplate(
      { templateId: template.id, programLengthWeeks: 4 },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    let view = await loadRequiredActiveWorkout(services);
    const firstSet = view.lifts[0]?.sets[0];

    if (!firstSet) {
      throw new Error("Expected first set.");
    }

    view = await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 12, actualWeight: 220 },
      services.workouts,
    );

    const overview = await loadProgramOverview(view.program.id, {
      appState: services.appState,
      programs: services.programs,
      analytics: services.analytics,
    });

    expect(overview?.program).toMatchObject({
      id: view.program.id,
      templateName: "Back In Action",
      workoutsPerWeek: 2,
      completedSets: 1,
      totalSets: 16,
      progressPercent: 6,
    });
    expect(overview?.schedule).toHaveLength(8);
    expect(overview?.schedule[0]).toMatchObject({
      workoutId: view.workout.id,
      isActive: true,
    });
    expect(overview?.schedule[0]?.statusCounts.complete).toBe(1);
    expect(overview?.schedule[0]?.statusCounts.active).toBe(1);
    expect(overview?.schedule[2]).toMatchObject({
      week: 2,
      day: 1,
      source: "planned",
      totalSets: 2,
    });
    expect(overview?.schedule[2]?.statusCounts.planned).toBe(2);
    expect(overview?.volumeRows).toEqual([
      expect.objectContaining({
        muscleName: "Chest",
        completedSets: 1,
        averageSetsPerWeek: 0.25,
      }),
    ]);
  });

  it("updates set and lift status when values are entered or cleared", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);
    const firstSet = view.lifts[0]?.sets[0];

    if (!firstSet) {
      throw new Error("Expected first set.");
    }

    view = await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 12, actualWeight: 220 },
      services.workouts,
    );

    expect(view.completedSets).toBe(1);
    expect(view.lifts[0]?.status).toBe("active");
    expect(view.lifts[0]?.sets[0]).toMatchObject({
      actualReps: 12,
      actualWeight: 220,
      status: "complete",
    });

    view = await updateWorkoutSet(
      { setId: firstSet.id, actualReps: null, actualWeight: 220 },
      services.workouts,
    );

    expect(view.completedSets).toBe(0);
    expect(view.lifts[0]?.status).toBe("active");
    expect(view.lifts[0]?.sets[0]).toMatchObject({
      actualReps: null,
      actualWeight: 220,
      status: "active",
    });
  });

  it("blocks active program replacement until confirmed, then halts and locks the old program", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    const oldView = await loadRequiredActiveWorkout(services);
    const firstSet = oldView.lifts[0]?.sets[0];

    if (!firstSet) {
      throw new Error("Expected first set.");
    }

    await updateWorkoutSet(
      { setId: firstSet.id, actualReps: 12, actualWeight: 220 },
      services.workouts,
    );

    await expect(startTemplateProgram(services, template.id)).rejects.toThrow("An active program already exists.");

    await startProgramFromTemplate(
      { templateId: template.id, programLengthWeeks: 4, replaceActiveProgram: true },
      {
        appState: services.appState,
        templates: services.templates,
        programs: services.programs,
      },
    );

    const newView = await loadRequiredActiveWorkout(services);
    const oldLockedView = await services.workouts.loadWorkoutView(oldView.workout.id);
    const appState = await services.appState.load();

    expect(newView.program.id).not.toBe(oldView.program.id);
    expect(newView.program.name).toBe("Back In Action x2");
    expect(appState).toMatchObject({
      activeProgramId: newView.program.id,
      activeWorkoutId: newView.workout.id,
    });
    expect(oldLockedView?.program).toMatchObject({ status: "halted", locked: true });
    expect(oldLockedView?.workout).toMatchObject({ status: "halted", locked: true });
    expect(oldLockedView?.lifts[0]).toMatchObject({ status: "halted", locked: true });
    expect(oldLockedView?.completedSets).toBe(1);
    expect(oldLockedView?.lifts[0]?.sets[0]).toMatchObject({ status: "complete", locked: true });
    expect(oldLockedView?.lifts[0]?.sets[1]).toMatchObject({ status: "halted", locked: true });
  });

  it("finishes workouts, activates the next workout, and creates the next week with progression", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1], [2]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    view = await completeWorkout(services, view, [10, 8], 100);
    expect(view.canFinish).toBe(false);

    view = await submitFeedbackForCompletedLifts(services, view);
    expect(view.canFinish).toBe(true);

    const dayTwo = await finishWorkout(view.workout.id, services.workouts);

    if (!dayTwo) {
      throw new Error("Expected day 2.");
    }

    expect(dayTwo.workout).toMatchObject({
      workoutDay: 2,
      programWeek: 1,
      status: "active",
      locked: false,
    });

    let completedDayTwo = await completeWorkout(services, dayTwo, [6, 5], 200);
    completedDayTwo = await submitFeedbackForCompletedLifts(services, completedDayTwo);
    const weekTwoDayOne = await finishWorkout(completedDayTwo.workout.id, services.workouts);

    if (!weekTwoDayOne) {
      throw new Error("Expected week 2 day 1.");
    }

    expect(weekTwoDayOne.workout).toMatchObject({
      workoutDay: 1,
      programWeek: 2,
      status: "active",
      locked: false,
    });
    expect(weekTwoDayOne.lifts[0]?.sets).toEqual([
      expect.objectContaining({ plannedReps: 11, plannedWeight: 100, actualReps: null }),
      expect.objectContaining({ plannedReps: 9, plannedWeight: 100, actualReps: null }),
    ]);
  });

  it("requires one feedback row for each completed lift before finishing", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    view = await completeWorkout(services, view, [12, 10], 220);

    expect(view.lifts[0]).toMatchObject({
      status: "complete",
      feedbackSubmitted: false,
    });
    expect(view.canFinish).toBe(false);
    await expect(finishWorkout(view.workout.id, services.workouts)).rejects.toThrow(
      "Submit feedback for every completed lift before finishing the workout.",
    );
    await expect(
      submitLiftFeedback(
        { liftId: view.lifts[0]?.id ?? 0, levelOfPain: 0, levelOfEffort: 3 },
        services.workouts,
      ),
    ).rejects.toThrow("Choose a feedback value from 1 to 5.");

    view = await submitLiftFeedback(
      { liftId: view.lifts[0]?.id ?? 0, levelOfPain: 1, levelOfEffort: 3 },
      services.workouts,
    );
    expect(view.lifts[0]?.feedbackSubmitted).toBe(true);
    expect(view.canFinish).toBe(true);

    view = await submitLiftFeedback(
      { liftId: view.lifts[0]?.id ?? 0, levelOfPain: 4, levelOfEffort: 5 },
      services.workouts,
    );
    expect(view.lifts[0]?.feedbackSubmitted).toBe(true);
    expect(view.canFinish).toBe(true);
  });

  it("clears active app state after the final workout and counts later program names", async () => {
    const services = createInMemoryAppServices();
    const template = await createTemplate(services, [[1]]);
    await startTemplateProgram(services, template.id);
    let view = await loadRequiredActiveWorkout(services);

    for (let week = 1; week <= 4; week += 1) {
      const completedView = await submitFeedbackForCompletedLifts(
        services,
        await completeWorkout(services, view, [10, 8], 100),
      );
      const nextView = await finishWorkout(completedView.workout.id, services.workouts);

      if (week < 4) {
        if (!nextView) {
          throw new Error("Expected next week workout.");
        }

        view = nextView;
      } else {
        expect(nextView).toBeNull();
      }
    }

    await expect(services.appState.load()).resolves.toMatchObject({
      activeProgramId: null,
      activeWorkoutId: null,
      activeLiftId: null,
    });

    await startTemplateProgram(services, template.id);
    const secondProgram = await loadRequiredActiveWorkout(services);

    expect(secondProgram.program.name).toBe("Back In Action x2");
  });
});

async function createTemplate(services: AppServices, exerciseIdsByDay: number[][]) {
  return saveTemplate(
    {
      name: "Back In Action",
      focusMuscleIds: [1],
      workoutsPerWeek: exerciseIdsByDay.length,
      days: exerciseIdsByDay.map((exerciseIds, index) => ({
        order: index + 1,
        exerciseIds,
      })),
    },
    services.templates,
  );
}

async function submitFeedbackForCompletedLifts(
  services: AppServices,
  view: ActiveWorkoutView,
): Promise<ActiveWorkoutView> {
  let nextView = view;

  for (const lift of view.lifts.filter((lift) => lift.status === "complete" && !lift.feedbackSubmitted)) {
    nextView = await submitLiftFeedback(
      { liftId: lift.id, levelOfPain: 1, levelOfEffort: 3 },
      services.workouts,
    );
  }

  return nextView;
}

async function startTemplateProgram(services: AppServices, templateId: number) {
  return startProgramFromTemplate(
    { templateId, programLengthWeeks: 4 },
    {
      appState: services.appState,
      templates: services.templates,
      programs: services.programs,
    },
  );
}

async function loadRequiredActiveWorkout(services: AppServices): Promise<ActiveWorkoutView> {
  const view = await services.workouts.loadActive();

  if (!view) {
    throw new Error("Expected active workout.");
  }

  return view;
}

async function completeWorkout(
  services: AppServices,
  view: ActiveWorkoutView,
  repsBySet: number[],
  weight: number,
): Promise<ActiveWorkoutView> {
  let nextView = view;

  for (const lift of view.lifts) {
    for (const set of lift.sets) {
      nextView = await updateWorkoutSet(
        {
          setId: set.id,
          actualReps: repsBySet[set.order - 1] ?? repsBySet[0] ?? 10,
          actualWeight: weight,
        },
        services.workouts,
      );
    }
  }

  return nextView;
}
